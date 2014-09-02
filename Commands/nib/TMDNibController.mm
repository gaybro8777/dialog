//
//  TMDNibController.mm
//  Dialog2
//

#import <string>
#import <map>
#import "../../Dialog2.h"
#import "../../TMDCommand.h"
#import "TMDNibController.h"

@interface TMDNibController (Private)
- (void)setParameters:(id)someParameters;
@end

@implementation TMDNibController
- (id)init
{
	if(self = [super init])
	{
		parameters = [NSMutableDictionary new];
		[parameters setObject:self forKey:@"controller"];

		clientFileHandles = [NSMutableArray new];
	}
	return self;
}

- (id)initWithNibPath:(NSString*)aPath
{
	if(self = [self init])
	{
		if(NSNib* nib = [[[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:aPath]] autorelease])
		{
			BOOL didInstantiate = NO;
			@try {
				didInstantiate = [nib instantiateNibWithOwner:self topLevelObjects:&topLevelObjects];
			}
			@catch(NSException* e) {
				// our retain count is too high if we reach this branch (<rdar://4803521>) so no RAII idioms for Cocoa, which is why we have the didLock variable, etc.
				NSLog(@"%s failed to instantiate nib (%@)", sel_getName(_cmd), [e reason]);
			}

			if(didInstantiate)
			{
				[topLevelObjects retain];
				for(id object in topLevelObjects)
				{
					if([object isKindOfClass:[NSWindow class]])
						[self setWindow:object];
				}

				if(window)
					return self;

				NSLog(@"%s failed to find window in nib: %@", sel_getName(_cmd), aPath);
			}
		}
		else
		{
			NSLog(@"%s failed loading nib: %@", sel_getName(_cmd), aPath);
		}
		[self release];
	}
	return nil;
}

- (void)dealloc
{
	[self setWindow:nil];
	[self setParameters:nil];

	for(id object in topLevelObjects)
		[object release];
	[topLevelObjects release];

	[clientFileHandles release];
	[super dealloc];
}

- (NSWindow*)window    { return window; }
- (id)parameters       { return parameters; }

- (void)setWindow:(NSWindow*)aWindow
{
	if(window != aWindow)
	{
		[window setDelegate:nil];
		[window release];
		window = [aWindow retain];
		[window setDelegate:self];
		[window setReleasedWhenClosed:NO]; // incase this was set wrong in IB
	}
}

- (void)setParameters:(id)someParameters
{
	if(parameters != someParameters)
	{
		[parameters release];
		parameters = [someParameters retain];
	}
}

- (void)updateParametersWith:(id)plist
{
	for(id key in [plist allKeys])
		[parameters setValue:[plist valueForKey:key] forKey:key];
}

- (void)showWindowAndCenter:(BOOL)shouldCenter
{
	if(shouldCenter)
	{
		if(NSWindow* keyWindow = [NSApp keyWindow])
		{
			NSRect frame = [window frame], parentFrame = [keyWindow frame];
			[window setFrame:NSMakeRect(NSMidX(parentFrame) - 0.5 * NSWidth(frame), NSMidY(parentFrame) - 0.5 * NSHeight(frame), NSWidth(frame), NSHeight(frame)) display:NO];
		}
		else
		{
			[window center];
		}
	}
	[window makeKeyAndOrderFront:self];
}

- (void)makeControllersCommitEditing
{
	for(id object in topLevelObjects)
	{
		if([object respondsToSelector:@selector(commitEditing)])
			[object commitEditing];
	}

	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)tearDown
{
	[parameters removeObjectForKey:@"controller"];

	// if we do not manually unbind, the object in the nib will keep us retained, and thus we will never reach dealloc
	for(id object in topLevelObjects)
	{
		if([object isKindOfClass:[NSObjectController class]])
			[object unbind:@"contentObject"];
	}
}

// ==================================
// = Getting stuff from this window =
// ==================================
- (void)addClientFileHandle:(NSFileHandle*)aFileHandle
{
	[clientFileHandles addObject:aFileHandle];
}

- (void)return:(NSDictionary*)eventInfo
{
	[self makeControllersCommitEditing];

	id model = [[parameters mutableCopy] autorelease];
	[model removeObjectForKey:@"controller"];

	NSDictionary* res = @{ @"model" : model, @"eventInfo" : eventInfo };

	for(NSFileHandle* fileHandle in clientFileHandles)
		[TMDCommand writePropertyList:res toFileHandle:fileHandle];

	[clientFileHandles removeAllObjects];
}

// ================================================
// = Events which return data to clients waiting  =
// ================================================
- (void)windowWillClose:(NSNotification*)aNotification
{
	[self return:@{ @"type" : @"closeWindow" }];
}

// ================================================
// = Faking a returnArgument:[…:]* implementation =
// ================================================
// returnArgument: implementation. See <http://lists.macromates.com/textmate/2006-November/015321.html>
- (NSMethodSignature*)methodSignatureForSelector:(SEL)aSelector
{
	NSLog(@"[%@ methodSignatureForSelector:%@]", [self class], NSStringFromSelector(aSelector));
	NSString* str = NSStringFromSelector(aSelector);
	if([str hasPrefix:@"returnArgument:"])
	{
		std::string types;
		types += @encode(void);
		types += @encode(id);
		types += @encode(SEL);

		NSUInteger numberOfArgs = [[str componentsSeparatedByString:@":"] count];
		while(numberOfArgs-- > 1)
			types += @encode(id);

		return [NSMethodSignature signatureWithObjCTypes:types.c_str()];
	}
	return [super methodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation*)invocation
{
	NSLog(@"[%@ forwardInvocation:%@]", [self class], invocation);
	NSString* str = NSStringFromSelector([invocation selector]);
	if([str hasPrefix:@"returnArgument:"])
	{
		NSArray* argNames = [str componentsSeparatedByString:@":"];

		NSMutableDictionary* res = [NSMutableDictionary dictionary];
		[res setObject:@"bindingAction" forKey:@"type"];

		for(NSUInteger i = 2; i < [[invocation methodSignature] numberOfArguments]; ++i)
		{
			id arg = nil;
			[invocation getArgument:&arg atIndex:i];
			[res setObject:(arg ?: @"") forKey:[argNames objectAtIndex:i - 2]];
		}

		[self return:res];
	}
	else
	{
		[super forwardInvocation:invocation];
	}
}

// ===============================
// = The old performButtonClicl: =
// ===============================
- (IBAction)performButtonClick:(id)sender
{
	NSMutableDictionary* res = [NSMutableDictionary dictionary];
	res[@"type"] = @"buttonClick";

	if([sender respondsToSelector:@selector(title)])
		res[@"title"] = [sender title];
	if([sender respondsToSelector:@selector(tag)])
		res[@"tag"] = @([sender tag]);

	[self return:res];
}
@end
