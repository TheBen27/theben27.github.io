---
title: 'A Typeclass Pattern for Kotlin'
header_image: '/images/kotlin-haskell-header.png'
...

If you learn a functional programming language, like Haskell, you get exposed to a bunch of interesting, weird ideas. Most of them are different ways of solving problems that imperative languages already have accepted solutions to, and trying to use them there can feel pointless or janky.

Typeclasses aren't quite like that. They're a bit like traits or interfaces, which might make them seem redundant, but they have a deceptive degree of flexibility. Even better, a popular library already uses typeclasses, even if it doesn't use that word, and I've extracted that pattern into this blog post.

This post is more a proof of concept or cool idea than a full library. The actual code to implement typeclasses isn't complicated, but a robust solution would require a codegen plugin with a lot of edge cases to handle. Still, it's an interesting tool to have in your kit, and a simple hand-spun version of typeclasses might be enough for your particular use case.

<!--more-->

This post requires some Kotlin knowledge, but shouldn't require any knowledge of typeclasses or functional programming whatsoever.

## Conceptual Typeclasses

Typeclasses are, roughly, interfaces whose implementations are decoupled from classes. Like an interface, a *typeclass* specifies one or more function signatures. For a given type, an *instance* of a typeclass fills in those functions. Unlike interfaces, instances of a typeclass are defined outside the class body, and can even be defined for existing classes.

Let's make a typeclass, `Comp`, which does the same thing as the standard library interface [`Comparable<T>`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin/-comparable/). It compares two values of the same type, returning 0 if both are equal, a positive number if the first is greater, and a negative number if the second is greater.

```kotlin
// Kotlin-shaped pseudocode
typeclass Comp<T> {
    fun compare(a: T, b: T): Int
}

instance Comp<Int> {
    fun compare(a: Int, b: Int): Int {
        return a - b
    }
}

instance Comp<String> {
    fun compare(a: String, b: String): Int {
        return a.compareTo(b)
    }
}

fun <T instancefor Comp> isSorted(list: List<T>): Boolean {
    return list.zipWithNext().all { (a, b) -> compare(a, b) <= 0 }
}
```

In this imaginary version of the Kotlin language, `isSorted` will work whenever the inner type of the list, `T`, has a `Comp` instance. So `Comp<Int>.isSorted()` would work, but `Comp<Float>.isSorted()` wouldn't.

This doesn't seem to have much of an advantage over interfaces at first, and in practice, I would usually recommend using interfaces over typeclasses in most situations. However, there is at least one major library that uses typeclasses already, even though it doesn't use the name "typeclasses".

[`kotlinx.serialization`](https://github.com/kotlin/kotlinx.serialization) is a library that converts objects to and from several different data formats, most commonly JSON. The function `Json.decodeFromString(json: String): T` tries to decode a JSON string into the type `T`. Under the hood, it gets an instance of `KSerializer` for the type `T`, if one exists, and uses that instance for the decoding. If it can't find an instance, it throws a runtime error.

`KSerializer` is essentially a typeclass with various instances for different `T`s: primitive types like `Int` or `ByteArray`, collections like `List`, user-defined types, sealed class hierarchies, etc. `decodeFromString` uses a `SerializersModule` to find or construct the right instances, which in turn uses a code generation plugin and runtime registration DSL. In short, it's building a function that maps from `T` to `KSerializer<T>` where possible, which is as close to typeclasses as you can get in most languages.

I'll describe a simpler version of this pattern, but first, we should go into where typeclasses have some clear benefit over interfaces.

### Why typeclasses?

The most obvious benefit to typeclasses is that you can add it to any class, even a class you don't  own, without changing it, which is nice but a bit superficial. After all, Kotlin has extension functions, and if those aren't enough, there's always wrapper classes.

More fundamentally, typeclasses can model a greater variety of patterns by dint of not being defined inside a class. Consider the hypothetical design of a `KSerializer` typeclass:

```kotlin
typeclass KSerializer<T> {
    fun decode(decoder: Decoder): T
    fun encode(value: T, encoder: Encoder)
}
```

The first function doesn't use or require an instance of `T`; it's essentially a static method whose behavior varies by type. We couldn't make this with a `Serializable` interface, because that function would be defined inside classes as an instance function.

This is still not that useful on its own. In most cases, you can just define multiple functions, one for each type, and let operator overloading decide which one to use. This is what Kotlin's standard library does for things like `map`:

```kotlin
fun <T, R> List<T>.map(mapper: (T) -> R): List<R>
fun <T, R> Array<T>.map(mapper: (T) -> R): List<R>
fun <R> IntArray.map(mapper: (Int) -> R): List<R>
```

This approach wouldn't work for `KSerializer`, though, because it needs to support "constrained" typeclass instances. For example, we can say that `Json.decodeFromString` should work for any `List<T>` as long as `T` itself works with `Json.decodeFromString`. In other words, `List<T>` is an instance of `KSerializer` with the *constraint* that `T` is an instance of `KSerializer`.

This means that we need to be able to "generate" instances of `KSerializer` for `List<Int>`, `List<String>`, `List<List<Pair<Int, List<String>>>`, and so forth, and as we'll see later, typeclasses handle this problem very elegantly.

You might wonder if a dependency injection framework could provide typeclass-like functionality. At a glance, Hilt cannot dynamically provide instances for a type `T`, and you would have to manually build every instance used in your project, but I'm not very well-versed in Hilt.

## A quick-and-dirty typeclass library

I'll use `kotlinx.serialization`'s approach for this post, so there's very little new information here. Still, `kotlinx.serialization` is a bit heavyweight, so I still think it's useful to describe a stripped-down, generic version of what it's doing.

To demonstrate the typeclass pattern, I'll make a typeclass `Arbitrary<T>`. Its only function, `arbitrary(): T`, generates a random value of type `T`. You could use this for [property testing](https://www.cse.chalmers.se/~rjmh/QuickCheck/manual.html), where you verify that many randomly generated inputs of a given type satisfy certain properties. The name "Arbitrary" is itself taken from the Haskell property testing library QuickCheck.

```kotlin
arbitrary<Int>() // -2130
arbitrary<Float>() // 0.00213
arbitrary<List<Int>>() // [-12, 3123, 0, 3212]
arbitary<List<Pair<Int, List<Float>>> // [2 to [0.32, 0.895, -0.1], 5 to [0.1, 0.3, 0.12]]
```

### The typeclass

A typeclass is just an interface, parameterized on the type of the implementing instance.

```kotlin
interface Arbitrary<T> {
    fun arbitrary(): T
}
```

Typeclasses can be more complicated than this. Most notably, they can "extend" each other, just like interfaces. We'll keep things simple and address this later.

### The instances

Each instance of a typeclass for a given type is an implementation of the interface for that type.

```kotlin
object ArbitraryInt : Arbitrary<Int> {
    override fun arbitrary(): Int {
        return Random.nextInt()
    }
}

object ArbitraryFloat : Arbitrary<Float> {
    override fun arbitrary(): Float {
        return Random.nextFloat()
    }
}
```

`ArbitraryInt` is the instance of `Arbitrary` for `Int`. Since `Int` is a concrete type, we can make this a singleton.

Constrained instances are a bit more complex. Consider an instance of `Arbitrary` for `Pair<A, B>`. The constraints are that `A` and `B` have to be instances of `Arbitrary`. The instance for `Pair` needs to be able to use those instances without knowing anything about them.

The solution is to make the instance a `class`, not an `object`, and to pass in the instances of `A` and `B` through the constructor.

```kotlin
class ArbitraryPair<A, B>(
    private val innerA: Arbitrary<A>,
    private val innerB: Arbitrary<B>,
) : Arbitrary<Pair<A, B>> {
    override fun arbitrary(): Pair<A, B> {
        return innerA.arbitrary() to innerB.arbitrary()
    }
}
```

We can do something similar for `List<T>`, which is constrained on `T` having an `Arbitrary` instance:

```kotlin
class ArbitraryList<T>(
    private val inner: Arbitrary<T>,
) : Arbitrary<List<T>> {
    override fun arbitrary(): List<T> {
        val size = randomInt(maxContainerSize)
        return (1..size).map { inner.arbitrary() } }
    }
}
```

### The registry

At this point, we can use our instances to manually build typeclasses for any type:

```kotlin
// List<Pair<Int, List<Float>>
ArbitraryList(ArbitraryPair(ArbitraryInt, ArbitraryList(ArbitraryFloat))).arbitrary()
```

However, it'd be a lot cleaner and easier if we could just write a type and have the program turn it into the right instance:

```kotlin
arbitrary<List<Pair<Int, List<Float>>>()
```

If typeclasses were a language feature, the compiler would be responsible for this transformation. Unfortunately, we need to build a *registry*: something that takes a type, modeled through the built-in Kotlin reflection object `KType`, and turns it into a typeclass instance (or fails and crashes). `kotlinx.serialization`'s registry uses some mix of a compiler plugin, runtime reflection, and dynamic instance registration to do this. For simplicity, we can just implement the latter:

```kotlin
open class TypeclassRegistry<T> {
    private val typeclasses: MutableMap<KClass<*>, (List<KType>) -> T> = mutableMapOf()

    fun registerSingle(kclass: KClass<*>, instance: T) {
        typeclasses[kclass] = { _ -> instance }
    }

    fun registerPolymorphic(kclass: KClass<*>, makeInstance: (List<KType>) -> T) {
        typeclasses[kclass] = makeInstance
    }

    fun getInstance(type: KType): T {
        val baseClass = type.classifier as KClass<*>
        val arguments = type.arguments.map { it.type!! }
        return typeclasses[baseClass]!!.invoke(arguments)
    }
}
```

`KType` is type (e.g. `List<Int>` or `Float`) as represented by Kotlin reflection. We split the type into the class and, if any, the type arguments: for example, `Pair<Int, Float>` becomes the `KClass` `Pair` and the `List<KType>` `listOf(Int, Float)`. It's then up to the registry to turn that into a typeclass instance.

For classes with no type arguments, we can ignore the type argument list (which will be empty) and return the same instance every time. This is the case `registerESingle` represents. Classes with type arguments use `registerPolymorphic`, which passes the types to a function that builds the final typeclass instance.

To resolve typeclass constraints, the implementation of `Arbitrary`'s registry uses `getInstance` recursively on its type arguments:

```kotlin
object ArbitraryTypeclassRegistry : TypeclassRegistry<Arbitrary<*>>() {
    init {
        registerSingle(Int::class, ArbitraryInt)
        registerSingle(Float::class, ArbitraryFloat)
        registerPolymorphic(Pair::class) { typeArguments ->
            ArbitraryPair(
                getInstance(typeArguments[0]),
                getInstance(typeArguments[1]),
            )
        }
        registerPolymorphic(List::class) { typeArguments ->
            ArbitraryList(getInstance(typeArguments[0]))
        }
    }
}
```

You might wonder why `TypeClassRegistry.registerPolymorphic` doesn't just run `getInstance` on the arguments before passing them to the block. This is so you can have an instance of one typeclass whose type argument is constrained on a different typeclass, or an instance with type arguments that aren't constrained at all.

The final step is everyone's favorite way to turn the mundane into magic, that being an inline function with a [reified type parameter](https://kotlinlang.org/docs/inline-functions.html#reified-type-parameters):

```kotlin
@Suppress("UNCHECKED_CAST")
inline fun <reified T> arbitrary(): T {
    val instance = ArbitraryTypeclassRegistry.getInstance(typeOf<T>()) as Arbitrary<T>)
    return instance.arbitrary()
}
```

The only reason we need `<reified T>` is for `typeOf<T>()`, which turns `T` into a `KType` at compile time.

This will let us write the code we presented at the beginning of the section:

```kotlin
arbitrary<Int>() // -2130
arbitrary<Float>() // 0.00213
arbitrary<List<Int>>() // [-12, 3123, 0, 3212]
arbitary<List<Pair<Int, List<Float>>> // [2 to [0.32, 0.895, -0.1], 5 to [0.1, 0.3, 0.12]]
```

## Potential improvements

### Performance

Right now, our registry generates a new instance of a typeclass every time the code asks for it. This isn't an issue for concrete instances, like `ArbitraryInt`, since they're just a singleton object, but it becomes a problem for `ArbitraryList` or `ArbitraryPair`.

```kotlin
// this makes three instances of ArbitraryList<Int> under the hood
arbitrary<List<Int>>()
arbitrary<List<Int>>()
arbitrary<List<Int>>()
```

`kotlinx.serialization` solves this with a big old cache. This also lets it skip the reflection it has to do to find `KSerializer<T>` instances for types, at least after the first time you use that particular type.

### Typeclass Extension

It's possible for typeclasses to extend one another, in much the same way interfaces can inherit one another. If typeclass A extends typeclass B, two things happen:

 * Types that are instances of typeclass A must also be instances of typeclass B
 * Functions using typeclass A can use the functionality of typeclass B

We can model this with inheritance on the typeclasses and delegation in the instances:

```kotlin
// Base typeclass
interface Eq<T> {
  fun equals(a: T, b: T): Boolean
}

// Extending typeclass via inheritance
interface Comp<T> : Eq<T> {
  fun greaterThan(a: T, b: T): Boolean
}

// Comp<T> functions can use Eq<T>
fun <T> Comp<T>.greaterOrEqual(a: T, b: T): Boolean {
    return greaterThan(a, b) || equals(a, b)
}

// Base instance
object IntEq : Eq<Int> {
    override fun equals(a: Int, b: Int): Boolean {
        return a == b
    }
}

// Derived instance via delegation
object CompEq : Comp<Int>, Eq<Int> by IntEq {
    override fun greaterThan(a: T, b: T): Boolean {
        return a > b
    }
}
```

This requires no changes to the registry.

### Mixing Typeclasses and OO Inheritance

Typeclass inheritance is simple, and OO inheritance is... fairly simple, but mixing both in one language raises some conceptual questions:

* If class A inherits class B, and class B is an instance of a typeclass, should class A "inherit" that instance?
* Can interfaces be instances of a typeclass? If so, do their implementations inherit that instance? If so, how do you handle the "multiple-inheritance" problems that result from allowing this?

The simplest option is to have typeclasses not care at all about inheritance. The current class or interface a value is cast as at runtime determines what typeclass you get for it.

```kotlin
// More weird pseudocode
open class Foo
interface Baz
class Bar : Foo, Baz

typeclass Typeclass<T> { fun saySomething(input: T) }
instance Foo Typeclass {
    fun saySomething(input: Foo) {
        println("Wow, what a $input")
    }
}
instance Baz Typeclass {
    fun saySomething(input: Baz) {
        println("That's really a $input")
    }
}
instance Bar Typeclass {
    fun saySomething(input: Bar) {
        println("Definitely a $input")
    }
}

fun main() {
    val bar = Bar()
    saySomething(bar) // Definitely a Bar@3fee733d
    saySomething(bar as Baz) // That's really a Bar@3fee733d
    saySomething(bar as Foo) // Wow, what a Bar@3fee733d
}
```

This is unsatisfying, because it means that casting a value can drastically change its behavior, even when you're casting it to an interface. This violates the [Liskov Substitution Principle](https://en.wikipedia.org/wiki/Liskov_substitution_principle), or in less academic terms, feels unintuitive.

You could possibly add rules to avoid these "overlapping" instances. For example, if a class is an instance of a typeclass, none of its inheritors can have an instance of that same typeclass. This feels arbitrary and inflexible, though.

There is probably no perfect solution, and it might simply be that typeclasses and class inheritance don't mix. [Scala](https://www.scala-lang.org/), a JVM language with class inheritance, traits, *and* typeclasses, seems to use the approach I've outlined here, but I haven't looked at it closely.

### Instance registration

In the pattern this post demonstrates, you have to register every instance of a typeclass manually, probably in one module or file during app initialization. This is tedious and would require some clever packaging to avoid cyclic imports. Could we somehow avoid this?

My first approach was to use `companion object { init { ... } }` to register the instances to a registry `object`. I believe that the `init` block for objects is run lazily, when something in the program references the object (or the class the companion object belongs to?), so we can't guarantee that the instance registration code ever runs. There might be a way to trick Kotlin into running initialization code eagerly, but it feels like a hacky solution. It might also create a [static initialization order fiasco](https://en.cppreference.com/cpp/language/siof) if two eager blocks depend on one another, but I have no proof of this.

`kotlinx.serialization`'s solution is a plugin to generate a list of instances at compile time, with the runtime DSL left for cases like open inheritance that the plugin can't handle. Implementing that is the difference between this blog post (which amounts to "hey, here's a neat idea") and a full library. `kotlinx.serialization` seems to directly work with compiler internals instead of `KSP` or `kapt`, but I don't see why `KSP` wouldn't be sufficient here.

## Higher-Kinded Types

Much of the power of typeclasses, at least in languages like Haskell, comes from their ability to work on higher-kinded types (types that take at least one type argument). For example, take the `Foldable` typeclass:

```kotlin
// This code sadly doesn't work - see below
interface Foldable<F> {
    fun <A, B> fold(collection: F<A>, initial: B, folder: (B, A) -> B): F<B>
}
```

`Foldable` works on classes like `List`, `Map`, and `Set` -- not a particular specialization like `List<Int>`, just `List`. Instances of `Foldable` would get a variety of functions (`sum`, `product`, `minimum`, `maximum`, `asList`, `all`, `any`) for free.

```kotlin
// This code doesn't work either
fun <F> Foldable<F>.all(collection: F<Boolean>): Boolean {
    return fold(collection, true) { a, b -> a && b }
}
```

Unfortunately, Kotlin does not support generic higher-kinded types like `F<A>` or `F<Boolean>`. It is possible to "hack" in support for sort of thing, which is beyond the scope of this article, but I will outline the general approach. The JVM-specific standard is [KindedJ](https://github.com/KindedJ/KindedJ), based on an [OCaml paper](https://www.cl.cam.ac.uk/~jdy22/papers/lightweight-higher-kinded-polymorphism.pdf) from 2014.

In short, a "Witness" object represents `F`, and the interface `Ap<Witness, T>` represents `F<T>`. The program converts between the opaque interface `Ap<Witness, T>` and `F<T>` through functions or, if possible, subtyping.

```kotlin
interface Ap<F, T>

object ListWitness
class ListWrapper<T>(val inner: List<T>): Ap<ListWitness, T>

fun <T> List<T>.toAp(): Ap<ListWitness, T> {
    return ListWrapper(this) as Ap<ListWitness, T>
}

fun <T> Ap<ListWitness, T>.fromAp(): List<T> {
    return (this as ListWrapper<T>).inner
}
```

`Foldable`, its instances, and its registry use `Ap<ListWitness, _>` instead of `List`:

```kotlin
interface Foldable<T> {
    fun <A, B> fold(collection: Ap<T, A>, initial: B, folder: (B, A) -> B): B
}

class ListFoldable : Foldable<ListWitness> {
    override fun <A, B> fold(
        collection: Ap<ListWitness, A>,
        initial: B,
        folder: (B, A) -> B)
    ): B {
        collection.fromAp().fold(initial, folder).toAp()
    }
}

inline fun <reified F, A, B> fold(collection: Ap<F, A>, initial: A, folder: (B, A) -> A) {
    ...
}

fold(listOf(1, 2).toAp(), 0) { a, b -> a + b } // 3
```

[This sketch](https://pl.kotl.in/jzoRaIcKe) shows a potential way to write a registry and support constraints.

Having to use the `KindedJ` pattern adds additional complexity and novelty throughout the program.

## Conclusion

Over the years, most programming languages accumulate many ways to do the same thing, each with their own tradeoffs. Kotlin already does most of what typeclasses do, although there are places where typeclasses shine. In another world, Kotlin could have modeled DSLs, effect systems, and functional methods like `zipWithNext` via typeclasses, and it may have saved some code at the cost of having a higher barrier to entry for programmers.

To me, Kotlin feels like an attempt at "modernizing" Java - making it more concise and informal, adding a bunch of neat and useful tools to address Java's most grating or outdated elements, but otherwise having the same fundamental approach. It certainly spent a lot of time and effort (in my memory) making the transition from Java to Kotlin as painless as possible, even for existing projects. Adding typeclasses feels philosophically against that.

At some point while writing this, I learned that Scala supports typeclasses, classes, and traits. It's something I'd really like to learn more about, since I was confused about how you would combine classes and typeclasses.

In any case, I've found that learning about weird ideas in programming exposes you to new and sometimes very effective ways of doing things, even if different programming languages have to implement them in different ways.

Next time, I'll (probably) cover subtyping and casting in Haskell, which natively has neither of those things and probably shouldn't.
