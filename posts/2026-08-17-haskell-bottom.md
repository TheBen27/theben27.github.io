---
title: 'Absolute Failure: Haskell''s Bottom Type(s?)'
...

What is the type of a function that loops forever, or crashes the program? How do you represent a function that can't normally be called, or parameterize a type so that some of its terms become uncontructible?

All of these problems can be handled through the Bottom Type, a type that's easy to write but has truly bizarre behavior. This type shows up in plenty of languages, Haskell among them, but Haskell is unique in that it has two very different ways of representing this type.

This post assumes some basic knowledge of Haskell or knowledge of other programming languages. I will try to explain Haskell concepts when they stray from "normal" languages, but you might have to take some comments on faith.

## Starting at (the) bottom

To understand how Haskell handles the bottom type, we should start by understanding what the bottom type is modeling. A total failure state, which we call "bottom", is universal to all programming languages, and refers to non-termination (an infinite loop) or total program failure (abort/crashing). It is in contrast to successfully completing, or "halting".

> The term "bottom" shows up in propositional logic as meaning "contradiction" or "the proposition that can never be proven". I'm not sure if that's where the term came from, though.

There is no algorithm that, for every possible program, decides if a program (or part of a program) can result in bottom or not. We call this the Halting Problem, which is rather famous, but confused me a bit when I was younger.

When I first heard about the halting problem, I took it to mean that you could never prove if any program in a Turing complete language halted or not, no matter how simple. It is more correct to say that a perfect general purpose halt-detector is impossible, a logical contradiction, because if you had one, you could write a program that logically halts and does not halt at the same time:

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

You can absolutely prove that certain programs do or don't halt, but most languages do not provide a mechanism to 1) express that proof and 2) do something with it. Some do, which is fascinating, but most don't, including Haskell. Because of this, at a theoretical level, bottom has to be a possible output of (and thus input to) every computation. To model this, bottom is considered a term of every type of a programming language.

> *Types* are formally sets of one or more *terms*. For example, we say the type `Boolean` has the terms `True` and `False`. The type `Int` has every 64-bit signed integer as its terms. Types can have anywhere from zero to an infinite number of terms.

Most programming languages, including Haskell, do not literally add `bottom` as a term of every type. It's simply how we use bottom in our mathematical models of how programs behave (what we call denotational semantics).

A function that returns `Boolean` could return `False`, `True`, or loop forever/crash, `bottom`ing out. A function that takes `Boolean` as an argument can receive `True`, `False`, or `bottom`.

`bottom` is obviously an unusual term. A function that takes a `Boolean` as an argument can check `arg == False`, but not `arg == bottom`, because that'd require the impossible general-purpose does-it-halt checker. We need `bottom` to be something functions can't reason about. What exactly that means depends on what programming language you're using, and Haskell (of course) does something weird here...

### Strict or non-strict?

Most programming languages are *strict* by default. The value of a computation is calculated when it is called in the code, regardless of if or when that value is used.

Haskell is, in contrast, *non-strict*. The value of a computation is only calculated when that value is used elsewhere in the code. This idea is very unusual and has dozens of implications to the behavior and performance of Haskell code, not all of them good, but for our purposes, it changes how we handle `bottom`.

Let's say we have a function in a strict C-like language that always returns `bottom` (crashes), called `crash`. Let's also say that its return type can be anything you want.

```c
int alwaysReturnFive(int a) {
    return 5;
}

int main() {
    printf("%d\n", alwaysReturnFive(crash()));
}
```

Even though `alwaysReturnFive` doesn't use the value of `a`, the argument is still evaluated before the function can be called. In our denotational semantics, we say that in a strict language, for any function `f`, `f(bottom) = bottom`.

This property prevents you from making a Halting Problem violator and is what makes `bottom` special - if you receive `bottom` as an argument, you cannot then output a more "defined" answer. You can't analyze or use `bottom` inside the function.

However, Haskell is not a strict language, and `f(bottom)` is not always `bottom`.

```haskell
-- Back to Haskell
alwaysReturnsFive :: Int -> Int
alwaysReturnsFive a = 5

main :: IO ()
main = print (alwaysReturnsFive abort)
```

Running this program prints `5`. In Haskell, function arguments are not concrete values, but instead computations that will only be run when necessary. Since `alwaysReturnsFive` never evaluates `abort`, `bottom` never comes, even though `abort` returns `bottom`.

The first implication of this is that `f(bottom) = bottom` if and only if `f` "uses" `bottom` in some way (is it "strict" in that argument). For example, the function below will crash when called with `abort` as its first argument, because it uses `x`:

```haskell
addOne :: Int -> Int
addOne x = x + 1
```

"Uses" is a vague term that probably means "returns or forces the evaluation of". The function `id x = x` doesn't force evaluation of `x`, but `id bottom = bottom`, so `id` is strict. In any case, because of this non-strictness, `bottom` is not an immediate failure in Haskell, and is instead a land mine of sorts that another function might walk over later.

The second implication is that `bottom` can get stored in data types. You can have a list of bottom, for example:

```haskell
bottoms :: [Int]
bottoms = [undefined, undefined, undefined]
```

If you try to use any of the elements of bottom, the program crashes. But, crucially, you can the length of the list without bottoming out, because you're only interacting with the structure of the list itself!

This complicates the hell out of `bottom` because now instead of a value being "defined" (not `bottom`) or "undefined" (`bottom`), some computations can be "more defined" than others. The list `[1]` is more defined than the list `[bottom]` which is defined than just `bottom`. For more information, see [this Wikibook](https://en.wikibooks.org/wiki/Haskell/Denotational_semantics).

> I'm calling Haskell "non-strict" and not "lazy", which is a more common term, for [pedantic reasons that don't matter](https://mail.haskell.org/pipermail/haskell-cafe/2007-November/034814.html).

## Bottom as a Type

You could write programs for years without ever hearing about `bottom`. While it is part of every type for the purposes of reasoning mathematically about programs, that's not how it's usually integrated into the language itself.

However, in most languages, you can find or make a type with the properties of `bottom`, which we will call `Bottom` with a capital `B`. Because conditional `bottom` is part of every type, this type represents unconditional `bottom`. A function that returns `Bottom` must crash or loop forever, and a function that takes a type `Bottom` as an argument must itself crash if it uses that argument in any way.

Note how `Bottom` is not just a marker for non-termination. It must be built in such a way that it is synonymous with absolute failure. It's a type that constrains the program instead of merely annotating it, which is why it's so interesting and useful.

### You can't make it

`Bottom` must be impossible to construct. If you could construct an instance of `Bottom`, you could write a function that returns `Bottom`, but exits normally:

```haskell
fail :: IO Bottom
fail = pureStrLn "Hah!" >> pure Bottom
```

This is a contradiction in terms. However, if `Bottom` can't be constructed...

```haskell
fail :: IO Bottom
fail = pureStrLn "Uh..." >> ...?
```

The only way to write a function returning `Bottom` is to have the function loop forever or crash, which is precisely what `Bottom` should mean.

Semantically, the type not being constructible is equilvalent to it having no terms (we call this an "uninhabited type" or "empty type"). Another way of looking at it is that `bottom` is the only term that the type `Bottom` can ever have.

### If you have it, you can do anything you want

The other property of `Bottom` is that you can turn `Bottom` into any other type -- there exists a function `Bottom -> a` for any type `a`. I've found this difficult to intuit, but I can motivate it in a few different ways.

One motivation for this is that `bottom` is a member of every type. If you can prove to the compiler that you have reached `bottom`, then you can say that any computations based on `bottom` are in any type.

More philosophically, code that tries to do something  with `bottom` will never run. If it's guaranteed on the type level that you've reached `bottom`, then whatever you do after that point doesn't matter, so you can do whatever you want.

This is analogous to the Principle of Explosion in propositional logic, the idea that you can derive any proposition if you start from a contradiction. This brutally confusing piece of documentation from Haskell's `Data.Void` module is referencing that.

> `absurd :: Void -> a`
> 
> Since Void values logically don't exist, this witnesses the logical reasoning tool of "ex falso quodlibet".

## Back to Haskell

Bottom types exist in a lot of languages. Wikipedia has a long list, but I have personally encountered `Nothing` in Kotlin and `never` in Typescript, and Haskell has its own version of that, `Data.Void`, which matches up with `Bottom` quite well.

However, Haskell's standard library doesn't use `Data.Void` to represent `bottom`. Compare Kotlin's `TODO` function with Haskell's `undefined` function. They both act as a placeholder for proper code, and both crash if called at runtime:

```kotlin
// Kotlin
inline fun TODO(): Nothing
```

```haskell
-- Haskell. Please ignore HasCallStack
undefined :: HasCallStack => a
```

Kotlin's function returns its bottom type, but Haskell returns something... different.

### Haskell's bottom type is `a`, sorta

`a` is not a concrete type, but a *type variable* to enable polymorphism in Haskell.

```haskell
id :: a -> a
id a = a
```

When calling `id`, you replace `a` with a concrete type as befits the situation.

```haskell
id 1
-- 1 :: Int
-- id :: Int -> Int
-- id 1 :: Int
```

> I'm calling it `a` for convenience, but any lowercase type in Haskell is a type variable. This lets you have multiple distinct type variables in the same function, e.g. `const :: a -> b -> a`.

`id` is a function that just returns the argument you gave it. It's simple, and in fact it has to be. The function knows nothing about `a`, it can't cast it, it can't check what type it is, it just knows that it exists, so barring some `unsafePerformIO` shenanigans, it can only return its argument.

> This is significantly different from some other languages, which tend to let you check/cast between types or have some general `toString()` or `hashCode()` operations that work on any type. This makes types much more powerful in Haskell at the cost of convenience.

> Yet another goddamn aside: Haskell uses typeclasses to achieve polymorphism, which can inherit from one another. Data types can't otherwise inherit one another or "share" functions.

Given what we've learned about types, what can this function do?

```haskell
undefined :: a
```

There's no way to make a value of any type out of thin air, so this function cannot terminate normally. It must result in `bottom`.

From a certain point of view, you could say `a` can't be constructed. From that same point of view, you'd say that `a` can be turned into any type. So while `a` isn't a type *per se*, it's definitely `Bottom`-esque, or at least an excellent way to represent `bottom`.

Now, `a` is not always a bottom type. `id :: a -> a` is clearly a function that can terminate normally. But if `a` is only present in the function's return type, it is practically a bottom type, even when the return type isn't just `a`.

```haskell
data Maybe a = Just a | Nothing

doesThisFail :: Maybe a
```

There are only three ways to implement `doesThisFail`: either always return `Nothing`, always return `Just [something that fails]`, or always return `bottom`.

Because `a` is only a bottom type in certain circumstances, it can't function as a bottom type in every situation.

```haskell
fooA :: a -> Int
foo a = a `seq` 5

fooVoid :: Void -> Int
foo a = a `seq` 5
```

`fooA` can be called with any value and will return `5` as long as `a` isn't `bottom`. `fooVoid` will only ever crash when called, because you have to pass in a value that crashed when evaluated.

> For the unfamiliar, Haskell is a non-strict language, and will usually only evaluate terms if and when they're actually used. `seq` forces the evaluation of its left-hand argument and then returns the right hand argument.
>
> Without `seq`, both of these functions would return `5`, because neither function uses its first argument for anything otherwise.

! Might be worth mentioning that infinite loops and empty case patterns are also of type `a`

### Haskell's bottom type is `Void`, kinda

`Void` is a concrete type that matches the conditions of the bottom type we've been building so far. Here is its implementation:

```haskell
-- This data type has no terms, and cannot be constructed
data Void

-- Void can be "converted" to any type
absurd :: Void -> a
absurd v = case v of {}
```

`case v of {}` is the thing most likely to throw you for a loop. `case` pattern matches on the possible terms of the type of `v`. Here's a more normal example of `case`:

```haskell
xor :: Boolean -> Boolean -> Boolean
xor a b =
    case a of { False -> b ; True -> not b }
```

However, since `Void` is empty, the `case` pattern is empty. The author could also write `undefined`, but this feels oddly elegant.

`Void` is more explicit and powerful than `a`. It can be used in situations where `a` would just mean "any value", not "guaranteed crash on evaluation". We already mentioned the difference between `fooA` and `fooVoid`:

```haskell
fooA :: a -> Int
foo a = a `seq` 5

fooVoid :: Void -> Int
foo a = a `seq` 5
```

The cases where `Void` is valuable but not `a` are limited, but they usually come down to polymorphism.

### Practical `Void`

I'm going to look at how a package called `Megaparsec` uses `Void`. `Megaparsec` is a "parser combinator" library for parsing text data.

> This is the part of the post that needs the most Haskell knowledge. I will do my best to explain things.

The library says that you should start by defining a type synonym of the `Parsec` data type for convenience. This is what it gives as an example:

```haskell
type Parser a = Parsec Void Text a
                       ^    ^
                       |    |
  Custom error component    Input stream type
```

Interesting. What does a `Void` custom error component mean?

`Parsec` is a data type that you can parameterize in different ways. You could have a `Parsec` with a different custom error component or a different input stream type. It is itself a type synonym for `ParsecM`, but we don't need to get into that:

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

So `parse` takes a `Parsec e s a` and returns *either* a result `a` or some error info, in the form of `ParseErrorBundle s e`.

Looking further:

```haskell
data ParseErrorBundle s e = ParseErrorBundle { bundleErrors :: NonEmpty (ParseError s e) }
```

That's just a wrapper around a list of `ParseError s e` that is guaranteed to not be empty.

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
    -- | Not really important what this is
  | ErrorIndentation Ordering Pos Pos
    -- | Oh, hey!
  | ErrorCustom e
  deriving (Show, Read, Eq, Ord, Data, Generic, Functor)
```

That was somewhat messy, but we can see that the type variable `e` gets sent down through the hierarchy.

```haskell
data ParseErrorBundle s e
  -> data ParseError s e
    -> data ErrorFancy e
```

If we parameterize `e` as `Void`, then we get `ErrorFancy Void`:

```haskell
data ErrorFancy Void
  = -- Unchanged...
    ErrorFail String
    -- Unchanged...
  | ErrorIndentation Ordering Pos Pos
    -- Hmm.
  | ErrorCustom Void
```

The parser can still make `ErrorFail` or `ErrorIndentation`, but the only way to construct an `ErrorCustom Void` is by passing in `bottom`. Even if you did this, the program would have no way to handle that error, so in practice, `Parsec Void s a` has no custom error type.

All of this is to say that usually, `Void` is helpful for making certain terms of a type "unconstructible", even if that type is buried deep in a hierarchy.

## So What is Haskell's Bottom Type?

Frankly, I'm not even sure that I know what a bottom type is. I could see arguments that `Void` and `a` are both bottom types, that only `Void` is a bottom type, or even that `Void` is not a bottom type in the strictest sense because Wikipedia defines bottom types as being at the bottom of a type hierarchy, which Haskell doesn't have as such.

You can use Haskell for quite a bit without using `Void`, but I find that exposing yourself to a wide variety of interesting concepts is a good way to stretch your problem solving skills. While bottom types show up in many languages, Haskell has a uniquely high number of weird, off-beat ideas that I enjoy exploring.
