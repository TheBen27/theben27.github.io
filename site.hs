--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
import Data.Aeson
import Data.Binary (Binary)
import Data.Typeable (Typeable)
import GHC.Generics (Generic)
import           Data.Monoid (mappend)
import           Hakyll
import qualified Data.ByteString.Lazy as BL
import Text.Pandoc.Highlighting (Style, kate, styleToCss)
import Text.Pandoc.Options (ReaderOptions (..), WriterOptions (..))


pandocCodeStyle :: Style
pandocCodeStyle = kate

renderPandoc' :: Item String -> Compiler (Item String)
renderPandoc' =
  renderPandocWith
    defaultHakyllReaderOptions
    defaultHakyllWriterOptions { writerHighlightStyle = Just pandocCodeStyle }

pandocCompiler' :: Compiler (Item String)
pandocCompiler' =
  pandocCompilerWith
    defaultHakyllReaderOptions
    defaultHakyllWriterOptions { writerHighlightStyle = Just pandocCodeStyle }

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

    create ["css/syntax.css"] $ do
      route idRoute
      compile $ do
        makeItem $ styleToCss pandocCodeStyle

    match "about.markdown" $ do
        -- Routes from {file.???} to {_site/file.html}
        route   $ setExtension "html"
        -- compile takes Compiler (Item a)
        -- Item is a Functor
        -- Compiler is a Monad
        -- relativizeUrls :: Item String -> Compiler (Item String)
        -- Traverse HTML and change absolute URLs to relative ones
        compile $ pandocCompiler'
            >>= loadAndApplyTemplate "templates/default.html" defaultContext
            >>= relativizeUrls

        -- loadAndApplyTemplate is actually a combination of loadBody "templates/default.html" and applyTemplate

    match "posts/*" $ do
        route $ setExtension "html"
        compile $ pandocCompiler'
            >>= loadAndApplyTemplate "templates/post.html"    postCtx
            >>= loadAndApplyTemplate "templates/default.html" postCtx
            >>= relativizeUrls

    -- This creates a file instead of matching
    -- create ["archive.html"] $ do
    --     route idRoute
    --     compile $ do
    --         -- You can load a single item (load) or multiple items (loadAll)
    --         -- This returns Compiler [Item String]
    --         -- Or consider loadBody
    --         posts <- recentFirst =<< loadAll "posts/*"
    --         -- Context objects are used for template substitution.
    --         -- Context is a monoid
    --         -- field :: String -> (Item a -> Context String) -> Context a
    --         -- field "body" $ \item -> pure (itemBody item) :: Context String
    --         let archiveCtx =
    --                 listField "posts" postCtx (return posts) `mappend`
    --                 constField "title" "Archives"            `mappend`
    --                 defaultContext
    --         -- defaultContext has $body$, $url$, $path$, $title$, $foo$ [metadata]
    --         -- $date$ is not provided by default, but dateField looks for date in item filename

    --         makeItem ""
    --             >>= loadAndApplyTemplate "templates/archive.html" archiveCtx
    --             >>= loadAndApplyTemplate "templates/default.html" archiveCtx
    --             >>= relativizeUrls
    --

    match "shaders.md" $ do
        route $ setExtension "html"
        compile $ do
          shaderInfo <- shadersCompiler =<< load "data/shaders.json"
          
          getResourceBody
            >>= applyAsTemplate (shadersCtx shaderInfo)
            >>= renderPandoc'
            >>= loadAndApplyTemplate "templates/default.html" postCtx
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

    match "data/shaders.json" $ compile getResourceLBS


--------------------------------------------------------------------------------
postCtx :: Context String
postCtx =
    dateField "date" "%B %e, %Y" `mappend`
    defaultContext

shadersCtx :: Item [Shader] -> Context a
shadersCtx shaders = listField "shaders" shaderCtx (pure $ sequenceA shaders)

shaderCtx :: Context Shader
shaderCtx =
  field "shader_title" (pure . shaderTitle . itemBody) `mappend`
  field "shader_url" (pure . shaderUrl . itemBody) `mappend`
  field "shader_img" (pure . shaderImg . itemBody)

shadersCompiler :: Item BL.ByteString -> Compiler (Item [Shader])
shadersCompiler input =
    case (decode (itemBody input)) :: Maybe [Shader] of
      Nothing -> fail "Could not parse shaders file"
      (Just s) -> pure (itemSetBody s input)

data Shader = Shader {
  shaderTitle :: String,
  shaderUrl :: String,
  shaderImg :: String
} deriving (Eq, Show, Typeable, Generic)

instance Binary Shader

instance FromJSON Shader where
  parseJSON = withObject "Shader" $ \v ->
    Shader <$> v .: "title" <*> v .: "url" <*> v .: "img"

-- Load shader data from a "database" file (becomes Item [Shader])
-- Function to build a context from a Shader
-- Use listField "shaders" shaderCtx (pure shaders)
