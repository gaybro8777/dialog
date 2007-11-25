//
//  Dialog2.mm
//  Dialog2
//
//  Created by Ciaran Walsh on 19/11/2007.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "Dialog2.h"
#import "TMDCommand.h"

@protocol TMPlugInController
- (float)version;
@end

@interface Dialog2 : NSObject <DialogServerProtocol>
{
}
- (id)initWithPlugInController:(id <TMPlugInController>)aController;
@end


@implementation Dialog2

- (id)initWithPlugInController:(id <TMPlugInController>)aController
{
	NSApp = [NSApplication sharedApplication];
	if (self = [self init]) {
		NSConnection *connection = [NSConnection new];
		[connection setRootObject:self];

		if ([connection registerName:DialogServerConnectionName] == NO)
			NSLog(@"couldn't setup dialog server."), NSBeep();
		else if (NSString* path = [[NSBundle bundleForClass:[self class]] pathForResource:@"tm_dialog2" ofType:nil]) {
			if (char* old_dialog = getenv("DIALOG_1"))
				setenv("DIALOG_1", old_dialog, 1);
			setenv("DIALOG", [path UTF8String], 1);
		}
	}

	return self;
}

- (void)dispatch:(id)options
{
	NSArray* args           = [options objectForKey:@"arguments"];
	NSString* cwd           = [options objectForKey:@"cwd"];
	NSFileHandle* stdin_fh  = [NSFileHandle fileHandleForReadingAtPath:[options objectForKey:@"stdin"]];
	NSFileHandle* stdout_fh = [NSFileHandle fileHandleForWritingAtPath:[options objectForKey:@"stdout"]];
	NSFileHandle* stderr_fh = [NSFileHandle fileHandleForWritingAtPath:[options objectForKey:@"stderr"]];

	NSDictionary* newOptions = [NSDictionary dictionaryWithObjectsAndKeys:
		stdin_fh,	@"stdin",
		stdout_fh,	@"stdout",
		stderr_fh,	@"stderr",
		args,			@"arguments",
		cwd,			@"cwd",
		nil];

	NSString* command = [args count] <= 1 ? @"help" : [args objectAtIndex:1];
	if(id target = [TMDCommand objectForCommand:command])
		[target performSelector:@selector(handleCommand:) withObject:newOptions];
	else
		[stderr_fh writeString:@"unknown command, try help.\n"];
}

- (void)hello:(id)options
{
	NSLog(@"%s %@", _cmd, options);
	[self performSelector:@selector(dispatch:) withObject:options afterDelay:0.0];
}
@end
/*
echo '{ menuItems = ({title = 'foo';});}' | "$DIALOG" menu
*/