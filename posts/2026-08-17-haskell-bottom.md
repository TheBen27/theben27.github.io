---
title: 'Absolute Failure: Haskell''s Bottom Type(s?)'
header_image: '/images/haskell-bottom-header.png'
...

What is the type of a function that loops forever, or crashes the program? How do you represent a function that can't normally be called, or parameterize a type so that some versions of it can't be created?

One solution is the bottom type, which is one of the simplest and weirdest concepts in programming. It's closely related to "bottom", something that is part of nearly every program but rarely shows up explicitly except through bottom types.

While bottom types show up in plenty of programming languages, Haskell in particular has two very different ways of representing bottom. I'll start by talking about bottom separate from any language, and then move into what Haskell does. I can't promise that this will be useful every day, but it's a mind-expanding sort of idea that might help you see new solutions to old problems.

<!--more-->

This post assumes some basic knowledge of Haskell or other programming languages. If you want learn Haskell, I can't recommend [Haskell Programming from First Principles](https://haskellbook.com/) enough, although you do have to pay for it. [Learn You a Haskell for Great Good!](https://learnyouahaskell.github.io/chapters.html) is free, but the lack of sample problems and exercises made it much harder for me to retain and think about what I was reading.

> The major sources for this post are [a Haskell wikibook](https://en.wikibooks.org/wiki/Haskell/Denotational_semantics) on denotational semantics, the [Bottom Haskell wiki](https://wiki.haskell.org/Bottom), Wikipedia pages, and Haskell documentation. While I didn't use it for this post, I recommend reading [this post](https://web.archive.org/web/20080819185521/http://www.thenewsh.com/~newsham/formal/curryhoward/) on the Curry-Howard correspondence and writing mathematical proofs in psuedo-Haskell. It won't help you understand this, it's just really interesting.

## Starting at (the) bottom

"Bottom" refers to non-termination (an infinite loop) or total program failure (abort/crashing). It is in contrast to successfully completing, or "halting". We say that any program, or a part of a program, "bottoms out" or "returns bottom" if it results in bottom.

> The term "bottom" shows up in propositional logic and means "a contradiction" or "the proposition that can never be proven". I'm not sure if that's where the term came from, though.

There is no algorithm that, for every possible program, decides if a program (or part of a program) can result in bottom or not. This is Alan Turing's famous [Halting Problem](https://en.wikipedia.org/wiki/Halting_problem).

When I first heard about the halting problem, I thought it meant you could never prove if *any* program in a Turing complete language halted or not, no matter how simple. The more complicated truth is that you can't make a halting detector that works for every possible program, because if you had one, you could write a program that simultaneously halted and did not halt:

```haskell
-- Halt if a program loops; loop if a program halts
halter :: Program -> ()
halter p =
  if halts p
    then halter p -- loop forever
    else () -- halt

-- Call halter on itself - Does this halt or not?
halter halter
```

You can absolutely prove that some programs always or never halt, but most languages do not provide a mechanism to 1) express that proof within the languge and 2) use that proof for optimization or safety. Some do, which is fascinating, but most don't, including Haskell. In those languages, at least at a theoretical level, bottom has to be a possible output of and input to every computation. To model this, for the purposes of reasoning about program behavior, bottom is considered a term of every type of a programming language.

> *Types* are formally sets of one or more *terms*. For example, we say the type `Boolean` has the terms `True` and `False`. The type `Int` has every 64-bit signed integer as its terms. Types can have anywhere from zero to an infinite number of terms.

Most programming languages, including Haskell, do not literally add `bottom` as a term of every type. But thinking of it this way is useful for "denotational semantics", the mathematical representation of a program's behavior.

So, for example, a function that returns `Boolean` could return `False`, `True`, or loop forever/crash, `bottom`ing out. A function that takes `Boolean` as an argument can receive `True`, `False`, or `bottom`.

What does it mean to receive `bottom` as an argument to a function? `bottom` is clearly not like other terms in a type. A function that takes a `Boolean` as an argument can check `arg == False`, but not `arg == bottom`, because that'd require the impossible does-it-halt checker. What exactly `bottom` is depends on the language, and Haskell (of course) diverges from the norm here...

### Strict or non-strict?

Most programming languages are *strict* by default. The value of a computation is calculated when it is called in the code, regardless of if or when that value is used.

Haskell is, in contrast, *non-strict*. The value of a computation is only calculated when that value is used. This idea is very unusual and has many implications for the behavior, performance, and design of Haskell, but for our purposes, it changes how we handle `bottom`.

Let's say we have a function in a strict C-like language that always crashes, called `crash`.

```c
int alwaysReturnFive(int a) {
    return 5;
}

int main() {
    printf("%d\n", alwaysReturnFive(crash()));
}
```

This program crashes. Even though `alwaysReturnFive` doesn't use the value of `a`, the argument (`crash()`) is still evaluated before the function can be called. In our denotational semantics, we say that in a strict language, for any function `f`, `f(bottom) = bottom`. This property prevents you from making a Halting Problem violator and is what makes `bottom` special - if you receive `bottom` as an argument, you can't do anything with it, because the program's already crashed.

However, Haskell is not a strict language, and `f(bottom)` is not always `bottom`.

```haskell
-- Back to Haskell
alwaysReturnsFive :: Int -> Int
alwaysReturnsFive a = 5

main :: IO ()
main = print (alwaysReturnsFive crash)
```

Running this program prints `5`. In a non-strict language, `a` is not a concrete value, but a computation that will be run when the value of `a` is first needed. Since `alwaysReturnsFive` never evaluates `crash`, `bottom` never comes.

In non-strict languages, `f(bottom) = bottom` when `f` returns the `bottom` it was given, tries to "use" the `bottom` in some way, or just returns `bottom` for no particular reason. For example, these functions will always crash when given `bottom` as input:

```haskell
-- Evaluates its input
addOne :: Int -> Int
addOne x = x + 1

-- Passes its argument forward with no changes
-- While it does not evaluate x, by definition, id bottom = bottom
id :: a -> a
id x = x

-- Just decides to crash for fun regardless of its input
-- (This technically counts as f bottom = bottom)
crash :: a -> b
crash _ = error "Oops!"
```

Data types, like functions, do not evaluate their arguments on construction. Because of this, data types can hold `bottom`. You can have a list of `bottom`s, for example:

```haskell
bottoms :: [Int]
bottoms = [undefined, undefined, undefined]
```

If you try to use any of the elements of `bottoms`, the program crashes. But, crucially, you can get the length of the list without bottoming out, because you're only interacting with the structure of the list itself, and not any of the underlying values:

```haskell
length :: [a] -> Int
-- A list with no elements has a length of 0
length [] = 0
-- A non-empty list can be split into its first element and zero or more
-- remaining elements. In this case, its length is 1, for the first element,
-- plus the length of the list of remaining elements.
length (_:xs) = 1 + length xs
```

This complicates the hell out of `bottom` because now instead of a value being "defined" (not `bottom`) or "undefined" (`bottom`), some computations can be "more defined" than others. The list `[1, 2, 3]` is more defined than the list `[undefined, undefined, undefined]` which is more defined than just `bottom`. For more information, see [this Wikibook](https://en.wikibooks.org/wiki/Haskell/Denotational_semantics).

> I'm calling Haskell "non-strict" and not "lazy", which is a more common term, for [pedantic reasons that don't matter](https://mail.haskell.org/pipermail/haskell-cafe/2007-November/034814.html).

## Bottom as a Type

You could write programs for years without ever caring about `bottom`. While it is part of every type for the purposes of mathematical reasoning about programs, that's not how it's usually integrated into the language itself.

In most languages, though, you can find or make a type with the properties of `bottom`, which we will call `Bottom` with a capital `B`. This type represents only one thing: unconditional `bottom`. A function that returns `Bottom` must crash or loop forever, and a function that takes a type `Bottom` as an argument must itself crash based on the conditions discussed in the last section.

`Bottom`, however, is not just a marker for failure. It must be built in such a way that it is synonymous with failure. It's a type that constrains the program instead of merely annotating it, which is why it's interesting and useful.

### You can't make it

`Bottom` must be impossible to return without crashing. If you could construct an instance of `Bottom`, you could write a function that returns `Bottom`, but exits normally:

```haskell
fail :: IO Bottom
fail = do
  pureStrLn "Hah!"
  return Bottom
```

This is a contradiction in terms. However, if `Bottom` can't be constructed...

```haskell
fail :: IO Bottom
fail = do
  pureStrLn "Uh..."
  return ... -- um...
```

The only way to write a function returning `Bottom` is to have the function loop forever or crash, which is precisely what `Bottom` should mean.

Semantically, the type not being constructible is equivalent to it having no terms (we call this an "uninhabited type" or "empty type"). Another way of looking at it is that `bottom` is the only term that the type `Bottom` can ever have.

### If you have it, you can do anything you want

The other property of `Bottom` is that you can turn `Bottom` into any other type -- equivalently, there exists a function `Bottom -> a` for any type `a`. This is hard for me to intuit, but I've tried to find a few motivations that make sense to me.

One motivation is that `bottom` is a member of every type. If you can prove to the compiler that you have reached `bottom`, then you can say that `bottom` is really a term of any type you want.

Another approach is to think about the type of endless recursion:

```
loopForever :: a
loopForever = loopForever 
```

This only returns `bottom` semantically but can logically be of any type.

More philosophically, code that tries to do something with `bottom` will never run. If it's guaranteed on the type level that you've reached `bottom`, then whatever you do after that point doesn't matter, so you can do whatever you want.

This is analogous to the Principle of Explosion in propositional logic, the idea that you can derive any proposition if you start from a contradiction. This documentation from Haskell's `Data.Void` module references that (in Latin for some reason).

> `absurd :: Void -> a`
> 
> Since Void values logically don't exist, this witnesses the logical reasoning tool of "ex falso quodlibet".

## Back to Haskell

Bottom types exist in a lot of languages. Wikipedia has a long list, but I have personally encountered `Nothing` in Kotlin and `never` in Typescript, and Haskell has its own version of that, `Data.Void`, which matches up with the `Bottom` we've described quite well.

However, Haskell's standard library doesn't use `Data.Void` to represent `bottom`. Compare Kotlin's `TODO` function with Haskell's `undefined` function. They both act as a placeholder for proper code, and both crash if called at runtime:

```kotlin
// Kotlin
inline fun TODO(): Nothing
```

```haskell
-- Haskell. Don't worry about HasCallStack
undefined :: HasCallStack => a
```

Kotlin's function returns its bottom type, but Haskell returns something... else.

### Haskell's bottom type is `a`, sorta

`a` is not a concrete type, but a *type variable* to enable polymorphism in Haskell.

```haskell
id :: a -> a
id a = a
```

When calling `id`, `a` becomes one specific type.

```haskell
id (1 :: Int)
-- id :: Int -> Int
-- id 1 :: Int
```

> I'm calling it `a` for convenience, but any lowercase type in Haskell is a type variable. This lets you have multiple distinct type variables in the same function, e.g. `const :: a -> b -> a`.

`id` is a function that just returns the argument you gave it. It's simple, and in fact it has to be. The function knows nothing about `a`, it can't cast it, it can't check what type it is, it just knows that it exists, so barring unusual shenanigans, it can only return its argument. This is significantly different from most other languages, which tend to let you check/cast between types or have some general `toString()` or `hashCode()` operations that work on any type. This makes types much more powerful in Haskell at the cost of convenience.

Given what we've learned about types, what can this function do?

```haskell
undefined :: a
```

There's no way to make a value of any type out of thin air, so this function cannot terminate normally. It must result in `bottom`, and in fact it crashes the program.

From a certain point of view, you could say `a` can't be constructed. From that same point of view, you'd say that `a` can be turned into any type. So while `a` isn't a type *per se*, it definitely looks like a `Bottom` type, or at least an excellent way to represent the concept of `bottom`.

`a` is not *always* a bottom type. `id :: a -> a` is clearly a function that can terminate normally. But if `a` is only present in the function's return type, it is practically a bottom type. This is still true if a type wraps around `a`, like `Maybe a`:

```haskell
-- A Maybe Int is either "Just an Int" or "Nothing" (like null)
data Maybe a = Just a | Nothing

-- This has only three possible implementations...
doesThisFail :: Maybe a
doesThisFail = Nothing

doesThisFail = Just undefined

doesThisFail = undefined

-- The type Maybe Void thus has three terms
```

Thus, the type `Maybe Void` has only three terms: `bottom`, `Just bottom`, and `Nothing`. This makes it isomorphic with `Boolean`, respectively corresponding to `bottom`, `True`, and `False`.

We know `a` can't function as a bottom type in every situation.

```haskell
fooA :: a -> Int
fooA a = a `seq` 5

fooVoid :: Void -> Int
fooVoid a = a `seq` 5
```

`seq` forces the evaluation of its left-hand argument and then returns the right-hand argument. In other words, it makes `fooA` and `fooVoid` strict in their first argument.

`fooA` can be called with any value and will return `5` as long as `a` isn't `bottom`. `fooVoid` will only ever crash when called, because you have to pass in a value that crashed when evaluated.

### Haskell's bottom type is `Void`, kinda

`Void` is a concrete type that matches the conditions of the bottom type we've been building so far. Here is its implementation:

```haskell
-- This data type has no terms, and cannot be constructed
data Void

-- Void can be "converted" to any type
absurd :: Void -> a
absurd v = case v of {}
```

`case v of {}` looks weird, but sort of makes sense. `case` patterns match on the possible terms of the type of `v`. Here's a more normal example of `case`:

```haskell
xor :: Boolean -> Boolean -> Boolean
xor a b =
    case a of { False -> b ; True -> not b }
```

Since `Void` has no terms to match on, the `case` pattern is empty. The author of `Data.Void`, Edward Kmett, could also have written `undefined`, but this feels oddly elegant.

`Void` is more explicit and powerful than `a`. It can be used in situations where `a` would just mean "any value", not "guaranteed crash on evaluation". We already mentioned the difference between `fooA` and `fooVoid`:

```haskell
fooA :: a -> Int
foo a = a `seq` 5

fooVoid :: Void -> Int
foo a = a `seq` 5
```

The cases where `Void` is valuable but not `a` are limited, but they usually come down to polymorphism.

### Practical `Void`

I'm going to show how a library called `Megaparsec` uses `Void`. `Megaparsec` is a "parser combinator" library for writing your own data parsers, usually of text files.

> This is the part of the post that needs the most Haskell knowledge. I will do my best to explain things.

The library says that you should start by defining a type synonym of the `Parsec` data type for convenience. This is what it gives as an example:

```haskell
type Parser a = Parsec Void Text a <- Return type of operation
                       ^    ^
                       |    |
  Custom error component    Input stream type
```

Interesting. What does a `Void` custom error component mean?

`Parsec` represents a parsing action that returns the parsed value, and has multiple type parameters, as shown above. You could have a `Parser` with a different custom error component or a different input stream type. It is itself a type synonym for `ParsecM`, but let's ignore that and focus on the type parameters:

```haskell
type Parsec e s a -- error, source, return value of parsing action
```

How do we use it?

```haskell
parse ::
  -- | Parser to run
  Parsec e s a ->
  -- | Name of source file
  String ->
  -- | Input for parser
  s ->
  Either (ParseErrorBundle s e) a
```

So `parse` takes a `Parsec e s a` and some other stuff and returns *either* error info, in the form of `ParseErrorBundle s e`, or a value `a`. Let's dig into `ParseErrorBundle`:

```haskell
data ParseErrorBundle s e = ParseErrorBundle { bundleErrors :: NonEmpty (ParseError s e) }
```

That's just a wrapper around a list of `ParseError s e` that is guaranteed to not be empty at compile time. What's a `ParseError`?

```haskell
data ParseError s e =
   TrivialError Int (Maybe (ErrorItem (Token s))) (Set (ErrorItem (Token s)))
 | FancyError Int (Set (ErrorFancy e))
```

So a `ParseError` can either be a `TrivialError`, with some information like where and how the error happened, or a set of `ErrorFancy`.

```haskell
data ErrorFancy e
  = -- | The user called "fail"
    ErrorFail String
    -- | I'm not sure what this is but it's not important
  | ErrorIndentation Ordering Pos Pos
    -- | Oh, hey! The error type.
  | ErrorCustom e
  deriving (Show, Read, Eq, Ord, Data, Generic, Functor)
```

That was somewhat messy, but we can see that the type variable `e` gets sent down through the hierarchy. We can also see that it's not used anywhere else.

```haskell
data ParseErrorBundle s e
  -> data ParseError s e
    -> data ErrorFancy e
```

If we parameterize `e` as `Void`, `Void` gets passed down through `ParseErrorBundle` and `ParseError` to `ErrorFancy`:

```haskell
data ErrorFancy Void
  = -- Unchanged...
    ErrorFail String
    -- Unchanged...
  | ErrorIndentation Ordering Pos Pos
    -- Hmm.
  | ErrorCustom Void
```

You can still make `ErrorFail` or `ErrorIndentation`, but the only way to construct an `ErrorCustom Void` is by passing in `bottom`. Even if you did this, the program would have no way to handle that error, so in practice, `Parsec Void s a` has no custom error type.

All of this is to say that usually, `Void` is helpful for making certain terms of a type "unconstructible", even if that type is buried deep in a hierarchy, without having to change the structure of the type.

## Conclusion

Haskell has at least one bottom type, `Void`, but in my mind, `a` is also a worthy candidate, especially since `Void` was only introduced in 2015. The Haskell 98 specification doesn't allow empty data types like `Void` -- to quote known Haskell guy [Simon Peyton Jones](https://simon.peytonjones.org/assets/pdfs/haskell-being-lazy-with-class.pdf), "at the time the value of such a type was not appreciated". It's possible now, but if it was possible from the beginning, would they have done something different?

I think `a`'s ability to automatically become any type, without the need for functions like `absurd`, makes it better than `Void` in the places it's currently used. On the other hand, `Void` has far more expressive power than `a` when  it comes to modeling behavior with types, and represents non-termination at a glance without any need to see where else it's used.

Empty types in Haskell go far beyond just `Void`. They're fairly common in [type-level metaprogramming](https://lexi-lambda.github.io/blog/2021/03/25/an-introduction-to-typeclass-metaprogramming/), which is way beyond the scope of this post. Empty types have no terms, but they can have type parameters, and when you're doing type-based computations, the terms a type can have don't really matter.
