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

#import "SMLRPhoneManager.h"

#import "SMLRCallStatus.h"
#import "SMLRLinphoneHandler.h"
#import "SMLRLog.h"
#import "SMLRPhoneManagerDelegate.h"

@interface SMLRPhoneManager () <SMLRLinphoneHandlerDelegate>

@property (nonatomic, weak) id<SMLRPhoneManagerRootViewControllerDelegate> rootViewControllerDelegate;
@property SMLRLinphoneHandler *linphoneHandler;
@property NSString *calleeSimlarId;
@property BOOL initializeAgain;

@end

@implementation SMLRPhoneManager

- (void)setDelegate:(id<SMLRPhoneManagerDelegate>)delegate
{
    self.linphoneHandler.phoneManagerDelegate = delegate;
}

- (void)setDelegateRootViewController:(id<SMLRPhoneManagerRootViewControllerDelegate>)delegateRootViewController
{
    self.rootViewControllerDelegate = delegateRootViewController;
}

- (void)checkForIncomingCall
{
    const SMLRLinphoneHandlerStatus status = [self.linphoneHandler getLinphoneHandlerStatus];
    SMLRLogI(@"checkForIncomingCall with status=%@", nameForSMLRLinphoneHandlerStatus(status));
    switch (status) {
        case SMLRLinphoneHandlerStatusDestroyed:
        case SMLRLinphoneHandlerStatusNone:
            [self initLibLinphone];
            break;
        case SMLRLinphoneHandlerStatusGoingDown:
            self.initializeAgain = YES;
            break;
        case SMLRLinphoneHandlerStatusInitializing:
            break;
        case SMLRLinphoneHandlerStatusFailedToConnectToSipServer:
            break;
        case SMLRLinphoneHandlerStatusConnectedToSipServer:
            if ([self.linphoneHandler hasIncomingCall]) {
                [self onIncomingCall];
            }
            break;
    }
}

- (void)initLibLinphone
{
    if (self.linphoneHandler) {
        SMLRLogI(@"WARNING liblinphone already initialized");
        return;
    }

    SMLRLogI(@"initializing liblinphone");
    self.linphoneHandler = [[SMLRLinphoneHandler alloc] init];
    self.linphoneHandler.delegate = self;
    [self.linphoneHandler initLibLinphone];
    SMLRLogI(@"initialized liblinphone");
}

- (void)terminateAllCalls
{
    [self.linphoneHandler terminateAllCalls];
}

- (void)acceptCall
{
    [self.linphoneHandler acceptCall];
}

- (void)saveSasVerified
{
    [self.linphoneHandler saveSasVerified];
}

- (void)callWithSimlarId:(NSString *const)simlarId
{
    switch ([self.linphoneHandler getLinphoneHandlerStatus]) {
        case SMLRLinphoneHandlerStatusDestroyed:
        case SMLRLinphoneHandlerStatusNone:
            self.calleeSimlarId = simlarId;
            [self initLibLinphone];
            break;
        case SMLRLinphoneHandlerStatusGoingDown:
        case SMLRLinphoneHandlerStatusInitializing:
            self.calleeSimlarId = simlarId;
            break;
        case SMLRLinphoneHandlerStatusFailedToConnectToSipServer:
            break;
        case SMLRLinphoneHandlerStatusConnectedToSipServer:
            self.calleeSimlarId = nil;
            if (![self.linphoneHandler hasIncomingCall]) {
                [self.linphoneHandler call:simlarId];
            } else {
                SMLRLogI(@"Skip calling %@ because of incoming call", simlarId);
                /// TODO think about
                //[self showIncomingCall];
            }
            break;
    }
}

- (void)onLinphoneHandlerStatusChanged:(SMLRLinphoneHandlerStatus)status
{
    SMLRLogI(@"onLinphoneHandlerStatusChanged: %@", nameForSMLRLinphoneHandlerStatus(status));

    if ([self.calleeSimlarId length] > 0 || self.initializeAgain) {
        switch (status) {
            case SMLRLinphoneHandlerStatusNone:
                SMLRLogI(@"ERROR onLinphoneHandlerStatusChanged: None");
                break;
            case SMLRLinphoneHandlerStatusGoingDown:
            case SMLRLinphoneHandlerStatusInitializing:
                break;
            case SMLRLinphoneHandlerStatusDestroyed:
                self.linphoneHandler = nil;
                [self initLibLinphone];
                break;
            case SMLRLinphoneHandlerStatusFailedToConnectToSipServer:
                /// TODO
                self.calleeSimlarId = nil;
                self.initializeAgain = NO;
                break;
            case SMLRLinphoneHandlerStatusConnectedToSipServer:
            {
                self.initializeAgain = NO;
                if ([self.calleeSimlarId length] > 0) {
                    NSString *const simlarId = self.calleeSimlarId;
                    self.calleeSimlarId = nil;
                    [self.linphoneHandler call:simlarId];
                }
                break;
            }
        }
    } else {
        switch (status) {
            case SMLRLinphoneHandlerStatusNone:
                SMLRLogI(@"ERROR onLinphoneHandlerStatusChanged: None");
                break;
            case SMLRLinphoneHandlerStatusGoingDown:
            case SMLRLinphoneHandlerStatusInitializing:
            case SMLRLinphoneHandlerStatusConnectedToSipServer:
                break;
            case SMLRLinphoneHandlerStatusFailedToConnectToSipServer:
                /// TODO
                break;
            case SMLRLinphoneHandlerStatusDestroyed:
                self.linphoneHandler = nil;
                break;
        }
    }
}

- (void)onIncomingCall
{
    SMLRLogI(@"incoming call");

    if (!self.rootViewControllerDelegate) {
        SMLRLogE(@"Error: incoming call but no root view controller delegate");
        return;
    }

    [self.rootViewControllerDelegate onIncomingCall];
}

- (void)onCallEnded
{
    SMLRLogFunc;

    if (!self.rootViewControllerDelegate) {
        SMLRLogE(@"Error: call ended but no root view controller delegate");
        return;
    }

    [self.rootViewControllerDelegate onCallEnded];
}

- (SMLRCallStatus)getCallStatus
{
    return [self.linphoneHandler getCallStatus];
}

- (NSString *)getCurrentCallSimlarId
{
    return [self.linphoneHandler getCurrentCallRemoteUser];
}

- (BOOL)hasIncomingCall
{
    return [self.linphoneHandler hasIncomingCall];
}

@end
