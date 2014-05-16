//
//  PlistModel.m
//  ShakeLog
//
//  Created by Logan Wright on 4/29/14.
//  Copyright (c) 2014 Logan Wright. All rights reserved.
//

#import "PlistModel.h"
#import <objc/runtime.h>

@interface PlistModel ()

@property (strong, nonatomic) NSMutableDictionary * realDictionary;
@property (strong, nonatomic) NSString * plistName;

@end

@implementation PlistModel

#pragma mark INITIALIZERS

+ (instancetype) plistNamed:(NSString *)plistName {
    return [[self alloc]initWithPlistName:plistName];
}

+ (void) plistNamed:(NSString *)plistName inBackgroundWithBlock:(void(^)(PlistModel * plistModel))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        
        PlistModel * newModel = [[self alloc]initWithPlistName:plistName];
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            completion(newModel);
        });
        
    });
}

- (instancetype)init {
    self = [super init];
    if (self) {
        
        // See if init was called properly, if not, we'll default to a plist with the class name
        if (!_plistName) {
            
            // If no plist is named, set it to class name:
            _plistName = NSStringFromClass(self.class);
            
            if ([_plistName isEqual:@"PlistModel"]) {
                // If Class is plistModel, then is not subclassed.  Set to "Info"
                _plistName = @"Info";
            }
            
        }
        
        // To make sure everything is set properly
        self = [self initWithPlistName:_plistName];
        
    }
    return self;
}

- (instancetype) initWithPlistName:(NSString *)plistName {
    self = [super init];
    if (self) {
        
        // Establish out plistName
        _plistName = plistName;
        
        // Step 1: Fetch PLIST & set to our backing dictionary
        _realDictionary = [NSMutableDictionary dictionaryWithDictionary:[self getPlist]];
        
        // Step 2: Find properties that exist in plist
        NSMutableSet * propertiesInPlist = [NSMutableSet setWithArray:[self getPropertyNames]];
        NSSet * allKeys = [NSSet setWithArray:_realDictionary.allKeys];
        [propertiesInPlist intersectSet:allKeys];
        
        // Step 3: Set properties to values from plist
        [propertiesInPlist enumerateObjectsUsingBlock:^(NSString * propertyName, BOOL *stop) {
            
            [self setPropertyFromDictionaryValueWithName:propertyName];
            
        }];
    }
    return self;
}

#pragma mark GET OUR PLIST

- (NSMutableDictionary *) getPlist {
    
    // Check to see if there's a Plist included in the main bundle
    NSString *path = [[NSBundle mainBundle] pathForResource:_plistName ofType: @"plist"];
    
    if (!path) {
        
        // There isn't already a plist, make one
        NSString * appendedPlistName = [NSString stringWithFormat:@"%@.plist", _plistName];
        
        // Fetch out plist & set to new path
        NSArray *pathArray = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [pathArray objectAtIndex:0];
        path = [documentsDirectory stringByAppendingPathComponent:appendedPlistName];
        
    }
    
    // If it doesn't exist, create it
    NSMutableDictionary * plist = [[NSMutableDictionary alloc]initWithContentsOfFile:path];
    
    // Return
    return plist;

}

#pragma mark GET OUR PROPERTY NAMES

- (NSMutableArray *) getPropertyNames {
    
    // Prepare Package
    NSMutableArray * propertyNames = [NSMutableArray array];
    
    // Fetch Properties
    unsigned count;
    objc_property_t *properties = class_copyPropertyList([self class], &count);
    
    // Parse Out Properties
    for (int i = 0; i < count; i++) {
        objc_property_t property = properties[i];
        const char * name = property_getName(property);
        // NSLog(@"Name: %s", name);
        const char * attributes = property_getAttributes(property);
        // NSLog(@"Attributes: %s", attributes);
        NSString * attributeString = [NSString stringWithUTF8String:attributes];
        NSArray * attributesArray = [attributeString componentsSeparatedByString:@","];
        if ([attributesArray containsObject:@"R"]) {
            // is ReadOnly
            NSLog(@"Properties can NOT be readonly to work properly.  %s will not be set", name);
        }
        else {
            // Add to our array
            [propertyNames addObject:[NSString stringWithUTF8String:name]];
        }
    }
    
    // Free our properties
    free(properties);
    
    // Send it off
    return propertyNames;
}

#pragma mark DEALLOC & SAVE - OK?

- (void) dealloc {
    
    // Save
    [self saveInBackgroundWithCompletion:nil];
    
}

- (void) saveInBackgroundWithCompletion:(void(^)(void))completion {
    
    // So we don't have to check it every time
    BOOL isInfo = [_plistName isEqualToString:@"Info"];
    
    // Set our properties to the dictionary before we write it
    for (NSString * propertyName in [self getPropertyNames]) {
        
        // Block our instance properties from setting to plist
        if ([propertyName isEqualToString:@"realDictionary"] || [propertyName isEqualToString:@"plistName"]) {
            // Block these properties
            continue;
        }
        
        // Check if we're using an Info.plist model
        if (!isInfo) {
            // If not Info.plist, don't set this variable.  The other properties won't be set, but because it's a BOOL, it will set a default 0;
            if ([propertyName isEqualToString:@"LSRequiresIPhoneOS"]) {
                continue;
            }
        }
        
        // Make sure our dictionary is set to show any updated properties
        [self setDictionaryValueFromPropertyWithName:propertyName];
    }
    
    // Set our block variables
    __block NSString * nameToSave = _plistName;
    __block NSDictionary * dictToSave = _realDictionary;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        
        NSString *path = [[NSBundle mainBundle] pathForResource:nameToSave ofType: @"plist"];
        if (!path) {
            
            // There isn't already a plist, make one
            NSString * plistName = [NSString stringWithFormat:@"%@.plist", nameToSave];
            
            // Fetch out plist
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *documentsDirectory = [paths objectAtIndex:0];
            path = [documentsDirectory stringByAppendingPathComponent:plistName];
        }
        
        // Write it to file
        [dictToSave writeToFile:path atomically:YES];
        
        // Run completion
        if (completion) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                completion();
            });
        }
    });
    
}

#pragma mark SELECTOR ARGUMENT / RETURN TYPE METHODS

- (const char *) returnTypeOfSelector:(SEL)selector {
    NSMethodSignature * sig = [self methodSignatureForSelector:selector];
    return [sig methodReturnType];
}

- (const char *) typeOfArgumentForSelector:(SEL)selector atIndex:(int)index {
    NSMethodSignature * sig = [self methodSignatureForSelector:selector];
    // Index 0 is object, Index 1 is the selector: arguments start at Index 2
    const char * argType = [sig getArgumentTypeAtIndex:index];
    return argType;
}

#pragma mark SELECTORS AND PROPERTIES STUFF

- (SEL) setterSelectorForPropertyName:(NSString *)propertyName {
    
    /*
     Because apple automatically generates setters to "setPropertyName:", we can use that and return the first argument to get the type of property it is.  That way, we can set it to our plist values.  Custom setters will cause problems.
     */
    
    // Make our first letter capitalized -  Using this because `capitalizedString` causes issues with camelCase => Camelcase
    NSString * capitalizedPropertyName = [propertyName stringByReplacingCharactersInRange:NSMakeRange(0,1) withString:[[propertyName substringToIndex:1] capitalizedString]];
    
    // The name of our auto synthesized setter | Custom setters will cause issues
    NSString * methodString = [NSString stringWithFormat:@"set%@:", capitalizedPropertyName];
    
    // Set our Selector
    SEL propertySetterSelector = NSSelectorFromString(methodString);
    
    // Return it
    return propertySetterSelector;
}

- (SEL) getterSelectorForPropertyName:(NSString *)propertyName {
    
    // AutoSynthesized Getters are just the property name
    return NSSelectorFromString(propertyName);
}

#pragma mark SYNCHRONYZING DICTIONARY AND PROPERTIES

- (void) setDictionaryValueFromPropertyWithName:(NSString *)propertyName {
    
    SEL propertyGetterSelector = [self getterSelectorForPropertyName:propertyName];
    
    const char * returnType = [self returnTypeOfSelector:propertyGetterSelector];
    
    if ([self respondsToSelector:propertyGetterSelector]) {
        
        // Get object from our dictionary
        // strcmp(str1, str2)
        // 0 if same
        // A value greater than zero indicates that the first character that does not match has a greater value in str1 than in str2;
        // And a value less than zero indicates the opposite.
        
        // Set our implementation
        IMP imp = [self methodForSelector:propertyGetterSelector];
        
        // Set to property
        if (strcmp(returnType, @encode(id)) == 0) {
            //NSLog(@"Is Object");
            id (*func)(id, SEL) = (void *)imp;
            id object = func(self, propertyGetterSelector);
            if (object) {
                _realDictionary[propertyName] = object;
            }
            else {
                [_realDictionary removeObjectForKey:propertyName];
            }
        }
        else if (strcmp(returnType, @encode(BOOL)) == 0) {
            //NSLog(@"Is Bool");
            BOOL (*func)(id, SEL) = (void *)imp;
            _realDictionary[propertyName] = @(func(self, propertyGetterSelector));
        }
        else if (strcmp(returnType, @encode(int)) == 0) {
            //NSLog(@"Is Int");
            int (*func)(id, SEL) = (void *)imp;
            _realDictionary[propertyName] = @(func(self, propertyGetterSelector));
        }
        else if (strcmp(returnType, @encode(float)) == 0) {
            //NSLog(@"Is Float");
            float (*func)(id, SEL) = (void *)imp;
            _realDictionary[propertyName] = @(func(self, propertyGetterSelector));
        }
        else if (strcmp(returnType, @encode(double)) == 0) {
            //NSLog(@"Is Double");
            double (*func)(id, SEL) = (void *)imp;
            _realDictionary[propertyName] = @(func(self, propertyGetterSelector));
        }
    }
}

- (void) setPropertyFromDictionaryValueWithName:(NSString *)propertyName {
    
    
    // Get our setter from our string
    SEL propertySetterSelector = [self setterSelectorForPropertyName:propertyName];
    
    // Make sure it exists as a property
    if ([self respondsToSelector:propertySetterSelector]) {
        
        
        if (_realDictionary[propertyName]) {
            
            // Index 0 is object, Index 1 is the selector: arguments start at Index 2
            const char * typeOfProperty = [self typeOfArgumentForSelector:propertySetterSelector atIndex:2];
            
            // Get object from our dictionary
            id objectFromDictionaryForProperty = _realDictionary[propertyName];
            
            // strcmp(str1, str2)
            // 0 if same
            // A value greater than zero indicates that the first character that does not match has a greater value in str1 than in str2;
            // And a value less than zero indicates the opposite.
            
            // Set our implementation
            IMP imp = [self methodForSelector:propertySetterSelector];
            
            // Set PlistValue to property
            if (strcmp(typeOfProperty, @encode(id)) == 0) {
                //NSLog(@"Is Object");
                void (*func)(id, SEL, id) = (void *)imp;
                func(self, propertySetterSelector, objectFromDictionaryForProperty);
            }
            else if (strcmp(typeOfProperty, @encode(BOOL)) == 0) {
                //NSLog(@"Is Bool");
                void (*func)(id, SEL, BOOL) = (void *)imp;
                func(self, propertySetterSelector, [objectFromDictionaryForProperty boolValue]);
            }
            else if (strcmp(typeOfProperty, @encode(int)) == 0) {
                //NSLog(@"Is Int");
                void (*func)(id, SEL, int) = (void *)imp;
                func(self, propertySetterSelector, [objectFromDictionaryForProperty intValue]);
            }
            else if (strcmp(typeOfProperty, @encode(float)) == 0) {
                //NSLog(@"Is Float");
                void (*func)(id, SEL, float) = (void *)imp;
                func(self, propertySetterSelector, [objectFromDictionaryForProperty floatValue]);
            }
            else if (strcmp(typeOfProperty, @encode(double)) == 0) {
                //NSLog(@"Is Double");
                void (*func)(id, SEL, double) = (void *)imp;
                func(self, propertySetterSelector, [objectFromDictionaryForProperty doubleValue]);
            }
            
        }
        else {
            
            // Index 0 is object, Index 1 is the selector: arguments start at Index 2
            const char * typeOfProperty = [self typeOfArgumentForSelector:propertySetterSelector atIndex:2];
            
            // strcmp(str1, str2)
            // 0 if same
            // A value greater than zero indicates that the first character that does not match has a greater value in str1 than in str2;
            // And a value less than zero indicates the opposite.
            
            // Set our implementation
            IMP imp = [self methodForSelector:propertySetterSelector];
            
            // Set PlistValue to property
            if (strcmp(typeOfProperty, @encode(id)) == 0) {
                //NSLog(@"Is Object");
                void (*func)(id, SEL, id) = (void *)imp;
                func(self, propertySetterSelector, [NSNull new]);
            }
            else if (strcmp(typeOfProperty, @encode(BOOL)) == 0) {
                //NSLog(@"Is Bool");
                void (*func)(id, SEL, BOOL) = (void *)imp;
                func(self, propertySetterSelector, NO);
            }
            else if (strcmp(typeOfProperty, @encode(int)) == 0) {
                //NSLog(@"Is Int");
                void (*func)(id, SEL, int) = (void *)imp;
                func(self, propertySetterSelector, 0);
            }
            else if (strcmp(typeOfProperty, @encode(float)) == 0) {
                //NSLog(@"Is Float");
                void (*func)(id, SEL, float) = (void *)imp;
                func(self, propertySetterSelector, 0);
            }
            else if (strcmp(typeOfProperty, @encode(double)) == 0) {
                //NSLog(@"Is Double");
                void (*func)(id, SEL, double) = (void *)imp;
                func(self, propertySetterSelector, 0);
            }
        }

    }
    
}

#pragma mark NSMutableDictionary Subclass OverRides -- NECESSARY!

- (void) setObject:(id)anObject forKey:(id<NSCopying>)aKey {
    
    if ([[(id)aKey class]isSubclassOfClass:[NSString class]]) {
        // Set the object to our background dictionary
        _realDictionary[aKey] = anObject;
        
        // Update our property -- Just to keep everything synced
        [self setPropertyFromDictionaryValueWithName:(NSString *)aKey];
    }
    else {
        NSLog(@"Error - Unable to add Object: Plist Model can only take strings as keys");
    }
    
}

- (void) removeObjectForKey:(id)aKey {
    
    if ([[(id)aKey class]isSubclassOfClass:[NSString class]]) {
        
        // Remove object from background dictionary
        [_realDictionary removeObjectForKey:aKey];
        
        // Update our property -- Just to keep everything synced
        [self setPropertyFromDictionaryValueWithName:(NSString *)aKey];
    }
    else {
        NSLog(@"Error - Unable to remove Object: Plist Model can only take strings as keys");
    }
}

- (NSUInteger) count {
    return _realDictionary.count;
}

- (id)objectForKey:(id)aKey {
    return _realDictionary[aKey];
}

- (NSEnumerator *)keyEnumerator {
    return [_realDictionary keyEnumerator];
}

@end
