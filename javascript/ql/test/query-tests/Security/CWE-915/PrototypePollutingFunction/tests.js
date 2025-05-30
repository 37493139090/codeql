import dummy from 'somewhere';

function copyUsingForIn(dst, src) {
    for (let key in src) { // $ Source
        if (dst[key]) {
            copyUsingForIn(dst[key], src[key]);
        } else {
            dst[key] = src[key]; // $ Alert
        }
    }
}

function copyUsingKeys(dst, src) {
    Object.keys(src).forEach(key => { // $ Source
        if (dst[key]) {
            copyUsingKeys(dst[key], src[key]);
        } else {
            dst[key] = src[key]; // $ Alert
        }
    });
}

function copyRest(dst, ...sources) {
    for (let source of sources) {
        for (let key in source) { // $ Source
            copyRestAux(dst, source[key], key);
        }
    }
}

function copyRestAux(dst, value, key) {
    let dstValue = dst[key];
    if (dstValue) {
        copyRest(dstValue, value);
    } else {
        dst[key] = value; // $ Alert
    }
}

function copyProtoGuarded(dst, src) {
    for (let key in src) { // $ Source
        if (key === "__proto__") continue;
        if (dst[key]) {
            copyProtoGuarded(dst[key], src[key]);
        } else {
            dst[key] = src[key]; // $ Alert
        }
    }
}

function copyCtorGuarded(dst, src) {
    for (let key in src) { // $ Source
        if (key === "constructor") continue;
        if (dst[key]) {
            copyCtorGuarded(dst[key], src[key]);
        } else {
            dst[key] = src[key]; // $ Alert
        }
    }
}

function copyDoubleGuarded(dst, src) {
    for (let key in src) {
        if (key === "constructor" || key === "__proto__") continue;
        if (dst[key]) {
            copyDoubleGuarded(dst[key], src[key]);
        } else {
            dst[key] = src[key];
        }
    }
}

function isSafe(key) {
    return key !== "__proto__" && key !== "constructor" && key !== "prototype";
}

function copyComplex(dst, src) {
    for (let key in src) {
        if (isSafe(key)) {
            if (dst[key]) {
                copyComplex(dst[key], src[key]);
            } else {
                dst[key] = src[key];
            }
        }
    }
}

function copyHasOwnProperty(dst, src) {
    for (let key in src) {
        // Guarding the recursive case by dst.hasOwnProperty is safe,
        // since '__proto__' and 'constructor' are not own properties of the destination object.
        if (dst.hasOwnProperty(key)) {
            copyHasOwnProperty(dst[key], src[key]);
        } else {
            dst[key] = src[key];
        }
    }
}

function copyHasOwnPropertyBad(dst, src) {
    for (let key in src) { // $ Source
        // Guarding using src.hasOwnProperty is *not* effective,
        // since '__proto__' and 'constructor' are own properties in the payload.
        if (!src.hasOwnProperty(key)) continue; // Not safe
        if (dst[key]) {
            copyHasOwnPropertyBad(dst[key], src[key]);
        } else {
            dst[key] = src[key]; // $ Alert
        }
    }
}

let _hasOwnProp = Object.prototype.hasOwnProperty;

function copyHasOwnPropertyTearOff(dst, src) {
    for (let key in src) {
        if (_hasOwnProp.call(dst, key)) {
            copyHasOwnPropertyTearOff(dst[key], src[key]);
        } else {
            dst[key] = src[key];
        }
    }
}

function shallowExtend(dst, src) {
    for (let key in src) {
        dst[key] = src[key];
    }
}

function transform(src, fn) {
    if (typeof src !== 'object') return fn(src);
    for (let key in src) {
        src[key] = transform(src[key], fn);
    }
    return src;
}

function clone(src) {
    if (typeof src !== 'object') return src;
    let result = {};
    for (let key in src) {
        result[key] = clone(src[key]);
    }
    return result;
}

function higherOrderRecursion(dst, src, callback) {
    for (let key in src) { // $ Source
        if (dst[key]) {
            callback(dst, src, key);
        } else {
            dst[key] = src[key]; // $ Alert
        }
    }
}

function higherOrderRecursionEntry(dst, src) {
    higherOrderRecursion(dst, src, (dst, src, key) => {
        higherOrderRecursionEntry(dst[key], src[key]);
    });
}

function instanceofObjectGuard(dst, src) {
    for (let key in src) {
        let dstValue = dst[key];
        if (typeof dstValue === 'object' && dstValue instanceof Object) {
            instanceofObjectGuard(dstValue, src[key]);
        } else {
            dst[key] = src[key];
        }
    }
}

let blacklist = ["__proto__", "constructor"];

function copyWithBlacklist(dst, src) {
    for (let key in src) {
        if (blacklist.indexOf(key) >= 0) continue;
        if (dst[key]) {
            copyWithBlacklist(dst[key], src[key]);
        } else {
            dst[key] = src[key];
        }
    }
}

function copyUsingPlainForLoop(dst, src) {
    let keys = Object.keys(src);
    for (let i = 0; i < keys.length; ++i) {
        let key = keys[i]; // $ Source
        if (dst[key]) {
            copyUsingPlainForLoop(dst[key], src[key]);
        } else {
            dst[key] = src[key]; // $ Alert
        }
    }
}

function copyUsingPlainForLoopNoAlias(dst, src) {
    // Like copyUsingPlainForLoop, but with keys[i] duplicated at every use-site
    let keys = Object.keys(src);
    for (let i = 0; i < keys.length; ++i) {
        if (dst[key]) {
            copyUsingPlainForLoopNoAlias(dst[keys[i]], src[keys[i]]);
        } else {
            dst[keys[i]] = src[keys[i]]; // $ MISSING: Alert
        }
    }
}

function deepSet(map, key1, key2, value) {
    if (!map[key1]) {
        map[key1] = Object.create(null);
    }
    map[key1][key2] = value;
}

function deepSetCaller(data) {
    let map1 = Object.create(null);
    let map2 = Object.create(null);
    for (let key in data) {
        deepSet(map1, key, 'x', data[key]);
        deepSet(map2, 'x', key, data[key]);
    }
}

function deepSetBad(map, key1, key2, value) {
    if (!map[key1]) {
        map[key1] = Object.create(null);
    }
    map[key1][key2] = value; // $ Alert - object literal can flow here
}

function deepSetCallerBad(data) {
    let map1 = Object.create(null);
    for (let key in data) { // $ Source
        deepSetBad({}, key, 'x', data[key]); // oops
        deepSetBad(map1, 'x', key, data[key]);
    }
}

function maybeCopy(x) {
    if (x && typeof x === 'object') {
        return {...x};
    } else {
        return x;
    }
}

function mergeWithCopy(dst, src) {
    if (dst == null) return src;
    let result = maybeCopy(dst);
    for (let key in src) {
        if (src.hasOwnProperty(key)) {
            result[key] = mergeWithCopy(dst[key], src[key]);
        }
    }
    return result;
}

function copyUsingEntries(dst, src) {
    Object.entries(src).forEach(entry => {
        let key = entry[0]; // $ Source
        let value = entry[1];
        if (dst[key]) {
            copyUsingEntries(dst[key], value);
        } else {
            dst[key] = value; // $ Alert
        }
    });
}

function copyUsingReflect(dst, src) {
    Reflect.ownKeys(src).forEach(key => { // $ Source
        if (dst[key]) {
            copyUsingReflect(dst[key], src[key]);
        } else {
            dst[key] = src[key]; // $ Alert
        }
    });
}

function copyWithPath(dst, src, path) {
    for (let key in src) {
        if (src.hasOwnProperty(key)) {
            if (dst[key]) {
                copyWithPath(dst[key], src[key], path ? path + '.' + key : key);
            } else {
                let target = {};
                target[path] = {};
                target[path][key] = src[key];
                doSomething(target);
            }
        }
    }
    return dst;
}

function typeofObjectTest(dst, src) {
    for (let key in src) { // $ Source
        if (src.hasOwnProperty(key)) {
            let value = src[key];
            if (dst[key] && typeof value === 'object') {
                typeofObjectTest(dst[key], value);
            } else {
                dst[key] = value; // $ Alert
            }
        }
    }
}

function mergeRephinementNode(dst, src) {
    for (let key in src) { // $ Source
        if (src.hasOwnProperty(key)) {
            if (key === key && key === key) continue; // Create a phi-node of refinement nodes
            let value = src[key];
            if (dst[key] && typeof value === 'object') {
                mergeRephinementNode(dst[key], value);
            } else {
                dst[key] = value; // $ Alert
            }
        }
    }
}

function mergeSelective(dst, src) {
    for (let key in src) { // $ Source
        if (src.hasOwnProperty(key)) {
            // Only 'prefs' is merged recursively
            if (key in dst && key !== 'prefs') {
                continue;
            }
            if (dst[key]) {
                mergeSelective(dst[key], src[key]);
            } else {
                dst[key] = src[key]; // $ Alert
            }
        }
    }
}

function isNonArrayObject(item) {
    return item && typeof item === 'object' && !Array.isArray(item);
}

function mergePlainObjectsOnly(target, source) {
    if (isNonArrayObject(target) && isNonArrayObject(source)) {
        Object.keys(source).forEach(key => { // $ Source
            if (key === '__proto__') {
                return;
            }
            if (isNonArrayObject(source[key]) && key in target) {
                target[key] = mergePlainObjectsOnly(target[key], source[key], options);
            } else {
                target[key] = source[key]; // $ SPURIOUS: Alert - due to imprecise barrier for captured variable
            }
        });
    }
    return target;
}

function mergePlainObjectsOnlyNoClosure(target, source) {
    if (isNonArrayObject(target) && isNonArrayObject(source)) {
        for (let key of Object.keys(source)) {
            if (key === '__proto__') {
                return;
            }
            if (isNonArrayObject(source[key]) && key in target) {
                target[key] = mergePlainObjectsOnlyNoClosure(target[key], source[key], options);
            } else {
                target[key] = source[key];
            }
        }
    }
    return target;
}

function forEachProp(obj, callback) {
    for (let key in obj) { // $ Source
        if (obj.hasOwnProperty(key)) {
            callback(key, obj[key]);
        }
    }
}

function mergeUsingCallback(dst, src) {
    forEachProp(src, key => {
        if (dst[key]) {
            mergeUsingCallback(dst[key], src[key]);
        } else {
            dst[key] = src[key]; // $ MISSING: Alert
        }
    });
}

function mergeUsingCallback2(dst, src) {
    forEachProp(src, (key, value) => {
        if (dst[key]) {
            mergeUsingCallback2(dst[key], value);
        } else {
            dst[key] = value; // $ Alert
        }
    });
}

function wrappedRead(obj, key) {
    return obj[key];
}

function copyUsingWrappedRead(dst, src) {
    for (let key in src) { // $ Source
        let value = wrappedRead(src, key);
        let target = wrappedRead(dst, key);
        if (target) {
            copyUsingWrappedRead(target, value);
        } else {
            dst[key] = value; // $ Alert
        }
    }
}

function almostSafeRead(obj, key) {
    if (key === '__proto__') return undefined;
    return obj[key];
}

function copyUsingAlmostSafeRead(dst, src) {
    for (let key in src) { // $ Source
        let value = almostSafeRead(src, key);
        let target = almostSafeRead(dst, key);
        if (target) {
            copyUsingAlmostSafeRead(target, value);
        } else {
            dst[key] = value; // $ Alert
        }
    }
}

function safeRead(obj, key) {
    if (key === '__proto__' || key === 'constructor') return undefined;
    return obj[key];
}

function copyUsingSafeRead(dst, src) {
    for (let key in src) {
        let value = safeRead(src, key);
        let target = safeRead(dst, key);
        if (target) {
            copyUsingSafeRead(target, value);
        } else {
            dst[key] = value;
        }
    }
}

function copyUsingForOwn(dst, src) {
    let forOwn = import('for-own');
    forOwn(src, (value, key, o) => { // $ Source
        if (dst[key]) {
            copyUsingForOwn(dst[key], src[key]);
        } else {
            // Handle a few different ways to access src[key]
            if (something()) dst[key] = src[key]; // $ Alert
            if (something()) dst[key] = o[key]; // $ Alert
            if (something()) dst[key] = value; // $ Alert
        }
    });
}

function copyUsingUnderscoreOrLodash(dst, src) {
    _.each(src, (value, key, o) => { // $ Source
        if (dst[key]) {
            copyUsingUnderscoreOrLodash(dst[key], src[key]);
        } else {
            dst[key] = value; // $ Alert
        }
    });
}

let isPlainObject = require('is-plain-object');
function copyPlainObject(dst, src) {
    for (let key in src) { // $ Source
        if (key === '__proto__') continue;
        if (dst[key] && isPlainObject(src)) {
            copyPlainObject(dst[key], src[key]);
        } else {
            dst[key] = src[key]; // $ SPURIOUS: Alert
        }
    }
}

function copyPlainObject2(dst, src) {
    for (let key in src) {
        if (key === '__proto__') continue;
        let target = dst[key];
        let value = src[key];
        if (isPlainObject(target) && isPlainObject(value)) {
            copyPlainObject2(target, value);
        } else {
            dst[key] = value;
        }
    }
}


function usingDefineProperty(dst, src) {
    let keys = Object.keys(src);
    for (let i = 0; i < keys.length; ++i) {
        let key = keys[i]; // $ Source
        if (dst[key]) {
            usingDefineProperty(dst[key], src[key]);
        } else {
            var descriptor = {};
            descriptor.value = src[key];
            Object.defineProperty(dst, key, descriptor);  // $ Alert
        }
    }
}

function copyUsingForInAndRest(...args) {
    const dst = args[0];
    const src = args[1];
    for (let key in src) { // $ Source
        if (dst[key]) {
            copyUsingForInAndRest(dst[key], src[key]);
        } else {
            dst[key] = src[key]; // $ Alert
        }
    }
}

function forEachPropNoTempVar(obj, callback) {
    const keys = Object.keys(obj)
    const len = keys.length
    for (let i = 0; i < len; i++) {
        callback(keys[i], obj[keys[i]]) // $ Source
    }
}

function mergeUsingCallback3(dst, src) {
    forEachPropNoTempVar(src, (key, value) => {
        if (dst[key]) {
            mergeUsingCallback3(dst[key], value);
        } else {
            dst[key] = value; // $ Alert
        }
    });
}

function copyHasOwnProperty2(dst, src) {
    for (let key in src) {
        // Guarding the recursive case by dst.hasOwnProperty (or Object.hasOwn) is safe,
        // since '__proto__' and 'constructor' are not own properties of the destination object.
        if (Object.hasOwn(dst, key)) {
            copyHasOwnProperty2(dst[key], src[key]);
        } else {
            dst[key] = src[key];
        }
    }
}

function copyHasOwnProperty3(dst, src) {
    for (let key in src) {
        // Guarding the recursive case by dst.hasOwnProperty (or Object.hasOwn) is safe,
        // since '__proto__' and 'constructor' are not own properties of the destination object.
        if (_.has(dst, key)) {
            copyHasOwnProperty3(dst[key], src[key]);
        } else {
            dst[key] = src[key];
        }
    }
}

function indirectHasOwn(dst, src) {
    for (let key in src) {
        if (!src.hasOwnProperty(key)) continue;
        if (hasOwn(dst, key) && isObject(dst[key])) {
            indirectHasOwn(dst[key], src[key]);
        } else {
            dst[key] = src[key];
        }
    }
}

function hasOwn(obj, key) {
    return obj.hasOwnProperty(key)
}

function captureBarrier(obj) {
	if (!obj || typeof obj !== 'object') {
		return obj; // 'obj' is captured but should not propagate through here
	}
    const fn = () => obj;
    fn();
    return "safe";
}

function merge_captureBarrier(dest, source) {
    for (const key of Object.keys(source)) { // $ Source
        if (dest[key]) {
            merge_captureBarrier(dest[key], source[key]);
        } else {
            dest[key] = captureBarrier(source[key]); // $ SPURIOUS: Alert
        }
    }
}
