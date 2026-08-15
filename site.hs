--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
import           Data.Monoid (mappend)
import           Hakyll


--------------------------------------------------------------------------------
main :: IO ()
main = hakyll $ do
    -- Consider this for string processing:
    -- https://hackage.haskell.org/package/hakyll-4.14.1.0/docs/Hakyll-Core-Routes.html
    -- route $ customRoute $ \s -> s

    -- Match against a Pattern.
    -- https://hackage.haskell.org/package/hakyll-4.14.1.0/docs/Hakyll-Core-Identifier-Pattern.html
    match "images/*" $ do
        -- Just keep the filename
        route   idRoute
        compile copyFileCompiler

    match "css/*" $ do
        route   idRoute
        compile compressCssCompiler

    match (fromList ["about.rst", "contact.markdown"]) $ do
        -- Routes from {file.???} to {_site/file.html}
        route   $ setExtension "html"
        -- compile takes Compiler (Item a)
        -- Item is a Functor
        -- Compiler is a Monad
        -- relativizeUrls :: Item String -> Compiler (Item String)
        -- Traverse HTML and change absolute URLs to relative ones
        compile $ pandocCompiler
            >>= loadAndApplyTemplate "templates/default.html" defaultContext
            >>= relativizeUrls

        -- loadAndApplyTemplate is actually a combination of loadBody "templates/default.html" and applyTemplate

    match "posts/*" $ do
        route $ setExtension "html"
        compile $ pandocCompiler
            >>= loadAndApplyTemplate "templates/post.html"    postCtx
            >>= loadAndApplyTemplate "templates/default.html" postCtx
            >>= relativizeUrls

    -- This creates a file instead of matching
    create ["archive.html"] $ do
        route idRoute
        compile $ do
            -- You can load a single item (load) or multiple items (loadAll)
            -- This returns Compiler [Item String]
            -- Or consider loadBody
            posts <- recentFirst =<< loadAll "posts/*"
            -- Context objects are used for template substitution.
            -- Context is a monoid
            -- field :: String -> (Item a -> Context String) -> Context a
            -- field "body" $ \item -> pure (itemBody item) :: Context String
            let archiveCtx =
                    listField "posts" postCtx (return posts) `mappend`
                    constField "title" "Archives"            `mappend`
                    defaultContext
            -- defaultContext has $body$, $url$, $path$, $title$, $foo$ [metadata]
            -- $date$ is not provided by default, but dateField looks for date in item filename

            makeItem ""
                >>= loadAndApplyTemplate "templates/archive.html" archiveCtx
                >>= loadAndApplyTemplate "templates/default.html" archiveCtx
                >>= relativizeUrls


    match "index.html" $ do
        route idRoute
        compile $ do
            posts <- recentFirst =<< loadAll "posts/*"
            let indexCtx =
                    listField "posts" postCtx (return posts) `mappend`
                    defaultContext

            getResourceBody
                >>= applyAsTemplate indexCtx
                >>= loadAndApplyTemplate "templates/default.html" indexCtx
                >>= relativizeUrls

    -- This loads templates for use in other items. We need to do this 
    -- even if we're loading templates in other places because templates
    -- can "include" other templates.
    match "templates/*" $ compile templateBodyCompiler


--------------------------------------------------------------------------------
postCtx :: Context String
postCtx =
    dateField "date" "%B %e, %Y" `mappend`
    defaultContext
