//  HTMLOrderedDictionary.m
//
//  Public domain. https://github.com/nolanw/HTMLReader

#import "HTMLOrderedDictionary.h"

@implementation HTMLOrderedDictionary
{
    CFMutableDictionaryRef _map;
    NSMutableArray *_keys;
}

- (id)initWithCapacity:(NSUInteger)numItems
{
    self = [super init];
    if (!self) return nil;
    
    _map = CFDictionaryCreateMutable(nil, numItems, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    _keys = [NSMutableArray arrayWithCapacity:numItems];
    
    return self;
}

// Diagnostic needs ignoring on iOS 5.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-parameter-types"
- (id)initWithObjects:(const id [])objects forKeys:(const id <NSCopying> [])keys count:(NSUInteger)count
#pragma clang diagnostic pop
{
    self = [self initWithCapacity:count];
    if (!self) return nil;
    
    for (NSUInteger i = 0; i < count; i++) {
        id object = objects[i];
        id key = keys[i];
        
        if (!object) [NSException raise:NSInvalidArgumentException format:@"%@ object at %@ cannot be nil", NSStringFromSelector(_cmd), @(i)];
        if (!key) [NSException raise:NSInvalidArgumentException format:@"%@ key at %@ cannot be nil", NSStringFromSelector(_cmd), @(i)];
        
        self[keys[i]] = objects[i];
    }
    
    return self;
}

// iOS 8 adds the NS_DESIGNATED_INITIALIZER attribute. Someday we should support that, but for now let's conveniently ignore it.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

- (id)init
{
    return [self initWithCapacity:0];
}

- (id)initWithCoder:(NSCoder *)coder
{
    NSDictionary *map = [coder decodeObjectForKey:@"map"];
    NSArray *keys = [coder decodeObjectForKey:@"keys"];
    HTMLOrderedDictionary *dictionary = [self initWithCapacity:keys.count];
    for (id key in keys) {
        dictionary[key] = map[key];
    }
    return dictionary;
}

#pragma clang diagnostic pop

- (void)dealloc
{
    CFRelease(_map);
}

- (Class)classForKeyedArchiver
{
    return [self class];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:(__bridge NSDictionary *)_map forKey:@"map"];
    [coder encodeObject:_keys forKey:@"keys"];
}

- (id)copyWithZone:(NSZone *)zone
{
    HTMLOrderedDictionary *copy = [[[self class] allocWithZone:zone] initWithCapacity:self.count];
    [copy addEntriesFromDictionary:self];
    return copy;
}

- (id)mutableCopyWithZone:(NSZone *)zone
{
    return [self copyWithZone:zone];
}

- (NSUInteger)count
{
    return _keys.count;
}

- (id)objectForKey:(id)key
{
    return (__bridge id)CFDictionaryGetValue(_map, (__bridge const void *)key);
}

- (NSUInteger)indexOfKey:(id)key
{
    if ([self objectForKey:key]) {
        return [_keys indexOfObject:key];
    } else {
        return NSNotFound;
    }
}

- (id)firstKey
{
    return _keys.firstObject;
}

- (id)lastKey
{
    return _keys.lastObject;
}

- (void)setObject:(id)object forKey:(id)key
{
    if (!object) [NSException raise:NSInvalidArgumentException format:@"%@ object cannot be nil", NSStringFromSelector(_cmd)];
    if (!key) [NSException raise:NSInvalidArgumentException format:@"%@ key cannot be nil", NSStringFromSelector(_cmd)];
    
    [self insertObject:object forKey:key atIndex:self.count];
}

- (void)removeObjectForKey:(id)key
{
    if (!key) [NSException raise:NSInvalidArgumentException format:@"%@ key cannot be nil", NSStringFromSelector(_cmd)];
    
    if ([self objectForKey:key]) {
        CFDictionaryRemoveValue(_map, (__bridge const void *)key);
        [_keys removeObject:key];
    }
}

- (void)insertObject:(id)object forKey:(id)key atIndex:(NSUInteger)index
{
    if (!object) [NSException raise:NSInvalidArgumentException format:@"%@ object cannot be nil", NSStringFromSelector(_cmd)];
    if (!key) [NSException raise:NSInvalidArgumentException format:@"%@ key cannot be nil", NSStringFromSelector(_cmd)];
    if (index > self.count) [NSException raise:NSRangeException format:@"%@ index %@ beyond count %@ of array", NSStringFromSelector(_cmd), @(index), @(self.count)];
    
    if (![self objectForKey:key]) {
        key = [key copy];
        [_keys insertObject:key atIndex:index];
    }
    CFDictionarySetValue(_map, (__bridge const void *)key, (__bridge const void *)object);
}

- (NSEnumerator *)keyEnumerator
{
    return _keys.objectEnumerator;
}

- (id)objectAtIndexedSubscript:(NSUInteger)index
{
    return _keys[index];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(__unsafe_unretained id [])buffer count:(NSUInteger)len
{
    return [_keys countByEnumeratingWithState:state objects:buffer count:len];
}

@end