/**
 * Copyright (C) 2014 The Simlar Authors.
 *
 * This file is part of Simlar. (https://www.simlar.org)
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

#import "SMLRReportBug.h"

#import "SMLRCredentials.h"
#import "SMLRLog.h"
#import "SMLRUploadLogFile.h"

#import <MessageUI/MessageUI.h>

@interface SMLRReportBug () <MFMailComposeViewControllerDelegate>

@property (nonatomic, weak) UIViewController *parentViewController;

@end


@implementation SMLRReportBug

static NSString *const EMAIL_ADDRESS = @"support@simlar.org";
static NSString *const EMAIL_TEXT    =
    @"Please put in your bug description here. It may be in German or English\n"
    @"\n\n\n"
    @"Please do not delete the following link as it helps developers to identify your logfile\n"
    @"\n"
    @"sftp://root@sip.simlar.org/var/www/simlar/logfiles/";

- (instancetype)initWithViewController:(UIViewController *const)viewController
{
    self = [super init];
    if (self) {
        self.parentViewController = viewController;
    }
    return self;
}

- (void)dealloc
{
    SMLRLogFunc;
}

- (void)reportBug
{
    SMLRLogFunc;

    if (![MFMailComposeViewController canSendMail]) {
        SMLRLogI(@"iphone is not configured to send mail");

        [[[UIAlertView alloc] initWithTitle:@"No EMail configured"
                                    message:@"You do not have an EMail app configured. This is mandatory in order to report a bug"
                                   delegate:nil
                          cancelButtonTitle:@"Abort"
                          otherButtonTitles:nil
          ] show];

        return;
    }

    UIAlertController *const alert = [UIAlertController alertControllerWithTitle:@"Report Bug"
                                                                         message:@"This will upload a log file. Afterwards you will be asked to write an email describing the bug.\n\nDo you want to continue?"
                                                                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Abort"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction * action) {
                                                SMLRLogI(@"reporting bug aborted by user");
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Continue"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * action) {
                                                [self uploadLogFile];
                                            }]];

    [self.parentViewController presentViewController:alert animated:YES completion:nil];
}

- (void)uploadLogFile
{
    SMLRLogFunc;

    [SMLRUploadLogFile uploadWithCompletionHandler:^(NSString *const logFileName, NSError *const error) {
        if (error != nil) {
            SMLRLogE(@"failed to upload logfile");

            // TODO handle offline case
            return;
        }

        [self writeEmailWithLogFileName:logFileName];
    }];
}

- (void)writeEmailWithLogFileName:(NSString *const)logFileName
{
    SMLRLogFunc;

    if (![MFMailComposeViewController canSendMail]) {
        SMLRLogI(@"iphone is not configured to send mail");
        return;
    }

    MFMailComposeViewController *const picker = [[MFMailComposeViewController alloc] init];
    [picker setMailComposeDelegate:self];
    [picker setSubject:@"Simlar iPhone bug report"];
    [picker setToRecipients:@[EMAIL_ADDRESS]];
    [picker setMessageBody:[NSString stringWithFormat:@"%@%@", EMAIL_TEXT, logFileName] isHTML:NO];

    [self.parentViewController presentViewController:picker animated:YES completion:nil];
}

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(const MFMailComposeResult)result error:(NSError *const)error
{
    SMLRLogFunc;
    [self.parentViewController dismissViewControllerAnimated:YES completion:nil];
}

@end