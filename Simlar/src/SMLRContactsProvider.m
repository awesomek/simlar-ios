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

#import "SMLRContactsProvider.h"

#import "SMLRContact.h"
#import "SMLRContactsProviderStatus.h"
#import "SMLRCredentials.h"
#import "SMLRGetContactStatus.h"
#import "SMLRHttpsPostError.h"
#import "SMLRLog.h"
#import "SMLRPhoneNumber.h"

#import <AddressBook/AddressBook.h>

//#define USE_FAKE_TELEPHONE_BOOK

@interface SMLRContactsProvider ()

@property (nonatomic) SMLRContactsProviderStatus status;
@property (nonatomic) NSDictionary *contacts;
@property (nonatomic) NSString *simlarIdToFind;
@property (nonatomic, copy) void (^simlarContactsHandler)(NSArray *const contacts, NSError *const);
@property (nonatomic, copy) void (^contactHandler)(SMLRContact *const contact, NSError *const);

@end

NSString *const SMLRContactsProviderErrorDomain = @"org.simlar.contactsProvider";

@implementation SMLRContactsProvider

- (void)getContactsWithCompletionHandler:(void (^)(NSArray *const contacts, NSError *const error))handler
{
    SMLRLogI(@"getContactsWithCompletionHandler with status=%@", nameSMLRContactsProviderStatus(_status));
    self.simlarContactsHandler = handler;

    switch (_status) {
        case SMLRContactsProviderStatusNone:
        case SMLRContactsProviderStatusError:
            [self checkAddressBookPermission];
            break;
        case SMLRContactsProviderStatusRequestingAddressBookAccess:
        case SMLRContactsProviderStatusParsingPhonesAddressBook:
        case SMLRContactsProviderStatusRequestingContactsStatus:
            break;
        case SMLRContactsProviderStatusInitialized:
        {
            NSMutableArray *const simlarContacts = [NSMutableArray array];
            for (SMLRContact *const contact in [_contacts allValues]) {
                if (contact.registered) {
                    [simlarContacts addObject:contact];
                }
            }

            [simlarContacts sortUsingSelector:@selector(compareByName:)];

            self.status = SMLRContactsProviderStatusInitialized;
            if (_simlarContactsHandler) {
                _simlarContactsHandler([SMLRContactsProvider groupContacts:simlarContacts], nil);
                self.simlarContactsHandler = nil;
            }
            break;
        }
    }
}

- (void)getContactBySimlarId:(NSString *const)simlarId completionHandler:(void (^)(SMLRContact *const contact, NSError *const error))handler
{
    SMLRLogI(@"getContactBySimlarId with status=%@", nameSMLRContactsProviderStatus(_status));

    self.contactHandler = handler;
    self.simlarIdToFind = simlarId;

    if ([simlarId length] == 0) {
        SMLRLogI(@"SimlarId is empty");
        [self handleErrorWithMessage:@"SimlarId is empty"];
        return;
    }

    switch (_status) {
        case SMLRContactsProviderStatusNone:
        case SMLRContactsProviderStatusError:
            [self checkAddressBookPermission];
            break;
        case SMLRContactsProviderStatusRequestingAddressBookAccess:
        case SMLRContactsProviderStatusParsingPhonesAddressBook:
            break;
        case SMLRContactsProviderStatusRequestingContactsStatus:
        case SMLRContactsProviderStatusInitialized:
            [self handleContactBySimlarId];
            break;
    }
}

- (void)reset
{
    if (_status == SMLRContactsProviderStatusInitialized) {
        SMLRLogI(@"resetting contacts");
        self.status = SMLRContactsProviderStatusNone;
    }
}

- (void)handleContactBySimlarId
{
    if (!_contactHandler || [_simlarIdToFind length] == 0) {
        return;
    }

    _contactHandler(_contacts[_simlarIdToFind], nil);
    self.contactHandler = nil;
    self.simlarIdToFind = nil;
}

+ (NSString *)createNameWithFirstName:(NSString *const)firstName lastName:(NSString *const)lastName
{
    if ([firstName length] > 0 && [lastName length] > 0) {
        return ABPersonGetSortOrdering() == kABPersonSortByFirstName
        ? [NSString stringWithFormat:@"%@ %@", firstName, lastName]
        : [NSString stringWithFormat:@"%@ %@", lastName, firstName];
    }

    return [firstName length] > 0 ? firstName : lastName;
}

- (void)handleError:(NSError *const)error
{
    self.status = SMLRContactsProviderStatusError;

    if (_simlarContactsHandler) {
        _simlarContactsHandler(nil, error);
        self.simlarContactsHandler = nil;
    }

    if (_contactHandler) {
        _contactHandler(nil, error);
        self.contactHandler = nil;
    }
}

- (void)handleErrorWithErrorCode:(const SMLRContactsProviderError)errorCode
{
    [self handleError:[NSError errorWithDomain:SMLRContactsProviderErrorDomain code:errorCode userInfo:nil]];
}

- (void)handleErrorWithMessage:(NSString *const)message
{
    [self handleError:[NSError errorWithDomain:SMLRContactsProviderErrorDomain
                                          code:SMLRContactsProviderErrorUnknown
                                      userInfo:@{ NSLocalizedDescriptionKey : message }]];
}

+ (NSString *)nameABAuthorizationStatus:(const ABAuthorizationStatus)status
{
    switch (status) {
        case kABAuthorizationStatusNotDetermined: return @"kABAuthorizationStatusNotDetermined";
        case kABAuthorizationStatusRestricted:    return @"kABAuthorizationStatusRestricted";
        case kABAuthorizationStatusDenied:        return @"kABAuthorizationStatusDenied";
        case kABAuthorizationStatusAuthorized:    return @"kABAuthorizationStatusAuthorized";
    }
}

- (void)checkAddressBookPermission
{
    SMLRLogFunc;

    const ABAuthorizationStatus status = ABAddressBookGetAuthorizationStatus();
    switch (status) {
        case kABAuthorizationStatusRestricted:
        case kABAuthorizationStatusDenied:
            SMLRLogI(@"AddressBook access denied: status=%@", [SMLRContactsProvider nameABAuthorizationStatus:status]);
            [self handleErrorWithErrorCode:SMLRContactsProviderErrorNoPermission];
            break;
        case kABAuthorizationStatusNotDetermined:
        case kABAuthorizationStatusAuthorized:
            SMLRLogI(@"AddressBook access granted: status=%@", [SMLRContactsProvider nameABAuthorizationStatus:status]);
            [self requestAddressBookAccess];
            break;
    }
}

- (void)requestAddressBookAccess
{
    SMLRLogI(@"start requesting access to address book");
    self.status = SMLRContactsProviderStatusRequestingAddressBookAccess;
    CFErrorRef error = NULL;
    const ABAddressBookRef addressBook = ABAddressBookCreateWithOptions(NULL, &error);

    if (error != NULL) {
        SMLRLogI(@"Error while creating address book reference: %@", error);
        if (addressBook != NULL) {
            CFRelease(addressBook);
        }
        [self handleError:(__bridge_transfer NSError *)error];
        return;
    }

    if (addressBook == NULL) {
        SMLRLogI(@"Error while creating address book reference");
        [self handleErrorWithMessage:@"Error while creating address book reference"];
        return;
    }

    ABAddressBookRequestAccessWithCompletion(addressBook, ^(const bool granted, const CFErrorRef requestAccessError) {
        dispatch_async(dispatch_get_main_queue(), ^(void){
            SMLRLogI(@"AddressBookRequestAccess granted=%d", granted);

            if (requestAccessError != NULL) {
                [self handleError:(__bridge_transfer NSError *)requestAccessError];
            } else if (!granted) {
                [self handleErrorWithErrorCode:SMLRContactsProviderErrorNoPermission];
            } else {
                [self readContactsFromAddressBook:addressBook];
            }

            CFRelease(addressBook);
        });
    });
}

- (void)readContactsFromAddressBook:(const ABAddressBookRef)addressBook
{
    SMLRLogI(@"start reading contacts from phones address book");
    self.status = SMLRContactsProviderStatusParsingPhonesAddressBook;

#ifndef USE_FAKE_TELEPHONE_BOOK
    NSArray *const allContacts = (__bridge_transfer NSArray *)ABAddressBookCopyArrayOfAllPeople(addressBook);

    NSMutableDictionary *const result = [NSMutableDictionary dictionary];
    for (id item in allContacts) {
        const ABRecordRef contact = (__bridge ABRecordRef)item;
        NSString *const firstName = (__bridge_transfer NSString*)ABRecordCopyValue(contact, kABPersonFirstNameProperty);
        NSString *const lastName  = (__bridge_transfer NSString*)ABRecordCopyValue(contact, kABPersonLastNameProperty);
        NSString *const name      = [SMLRContactsProvider createNameWithFirstName:firstName lastName:lastName];

        const ABMultiValueRef phoneNumbers = ABRecordCopyValue(contact, kABPersonPhoneProperty);
        for (CFIndex i = 0; i < ABMultiValueGetCount(phoneNumbers); i++) {
            NSString *const phoneNumber = (__bridge_transfer NSString *)ABMultiValueCopyValueAtIndex(phoneNumbers, i);
            if ([phoneNumber length] > 0) {
                if ([SMLRPhoneNumber isSimlarId:phoneNumber]) {
                    [result setValue:[[SMLRContact alloc]initWithSimlarId:phoneNumber
                                                       guiTelephoneNumber:phoneNumber
                                                                     name:name]
                              forKey:phoneNumber];
                } else {
                    SMLRPhoneNumber *const smlrPhoneNumber = [[SMLRPhoneNumber alloc] initWithNumber:phoneNumber];
                    if (![smlrPhoneNumber.getSimlarId isEqualToString:[SMLRCredentials getSimlarId]]) {
                        [result setValue:[[SMLRContact alloc] initWithSimlarId:[smlrPhoneNumber getSimlarId]
                                                            guiTelephoneNumber:[smlrPhoneNumber getGuiNumber]
                                                                          name:name]
                                  forKey:[smlrPhoneNumber getSimlarId]];
                    }
                }
            }
        }
        CFRelease(phoneNumbers);
    }

    self.contacts = result;
#else
    [self createFakeContacts];
#endif
    [self handleContactBySimlarId];
    [self getStatusForContacts];
}

+ (void)addContactToDictionary:(NSMutableDictionary *const)dictionary simlarId:(NSString *const)simlarId name:(NSString *const)name guiNumber:(NSString *const)guiNumber
{
    [dictionary setValue:[[SMLRContact alloc] initWithSimlarId:simlarId
                                            guiTelephoneNumber:guiNumber
                                                          name:name]
                  forKey:simlarId];
}

- (void)createFakeContacts
{
    NSMutableDictionary *const result = [NSMutableDictionary dictionary];

    [SMLRContactsProvider addContactToDictionary:result simlarId:@"*0002*" name:@"Barney Gumble"    guiNumber:@"+49 171 111111"];
    [SMLRContactsProvider addContactToDictionary:result simlarId:@"*0004*" name:@"Bender Rodriguez" guiNumber:@"+49 172 222222"];
    [SMLRContactsProvider addContactToDictionary:result simlarId:@"*0005*" name:@"Eric Cartman"     guiNumber:@"+49 173 333333"];
    [SMLRContactsProvider addContactToDictionary:result simlarId:@"*0006*" name:@"Earl Hickey"      guiNumber:@"+49 174 444444"];
    [SMLRContactsProvider addContactToDictionary:result simlarId:@"*0007*" name:@"H. M. Murdock"    guiNumber:@"+49 175 555555"];
    [SMLRContactsProvider addContactToDictionary:result simlarId:@"*0008*" name:@"Jackie Burkhart"  guiNumber:@"+49 176 666666"];
    [SMLRContactsProvider addContactToDictionary:result simlarId:@"*0003*" name:@"Peter Griffin"    guiNumber:@"+49 177 777777"];
    [SMLRContactsProvider addContactToDictionary:result simlarId:@"*0001*" name:@"Rosemarie"        guiNumber:@"+49 178 888888"];
    [SMLRContactsProvider addContactToDictionary:result simlarId:@"*0009*" name:@"Stan Smith"       guiNumber:@"+49 179 999999"];

    self.contacts = result;
}

- (void)getStatusForContacts
{
    SMLRLogI(@"start getting contacts status");
    self.status = SMLRContactsProviderStatusRequestingContactsStatus;

    [SMLRGetContactStatus getWithSimlarIds:[_contacts allKeys] completionHandler:^(NSDictionary *const contactStatusMap, NSError *const error) {
        if (error != nil) {
            if (isSMLRHttpsPostOfflineError(error)) {
                [self handleErrorWithErrorCode:SMLRContactsProviderErrorOffline];
                return;
            }

            [self handleError:error];
            return;
        }

        if (contactStatusMap == nil) {
            [self handleErrorWithMessage:@"empty contact status map"];
            return;
        }

        NSMutableArray *const simlarContacts = [NSMutableArray array];
        for (id simlarId in [contactStatusMap allKeys]) {
            SMLRContact *const contact = _contacts[simlarId];
            contact.registered = [(NSString *)contactStatusMap[simlarId] intValue] == 1;
            if (contact.registered) {
                [simlarContacts addObject:contact];
            }
        }

        SMLRLogI(@"Found %lu contacts registered at simlar", (unsigned long)[simlarContacts count]);

        [simlarContacts sortUsingSelector:@selector(compareByName:)];

        self.status = SMLRContactsProviderStatusInitialized;
        if (_simlarContactsHandler) {
            _simlarContactsHandler([SMLRContactsProvider groupContacts:simlarContacts], nil);
            self.simlarContactsHandler = nil;
        }
    }];
}

+ (NSArray *)groupContacts:(NSArray *const)sortedContacts
{
    if ([sortedContacts count] == 0) {
        return sortedContacts;
    }

    NSMutableArray *const groupedContacts = [NSMutableArray array];

    NSMutableArray *currentGroup = [NSMutableArray array];
    unichar currentGroupLetter   = '\0'; // no group letter

    for (SMLRContact *const contact in sortedContacts) {
        if ([contact getGroupLetter] != currentGroupLetter) {
            currentGroupLetter = [contact getGroupLetter];
            currentGroup = [NSMutableArray array];
            [groupedContacts addObject:currentGroup];
        }

        [currentGroup addObject:contact];
    }
    return groupedContacts;
}

@end
