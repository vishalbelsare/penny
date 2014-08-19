module Penny.Copper.Spaces where

import Control.Monad
import Penny.Numbers.Natural
import qualified Penny.Numbers.Natural as N
import Text.Parsec hiding (parse)
import Data.List (genericReplicate)
import qualified Data.Text as X
import Penny.Copper.Render
import Data.Monoid

newtype Spaces = Spaces { unSpaces :: Pos }
  deriving (Eq, Ord, Show)

instance Renderable Spaces where
  render = X.pack . flip genericReplicate ' '
    . unPos . unSpaces
  parse = do
    c <- many1 (char ' ')
    case nonNegToPos $ N.length c of
      Nothing -> error "spaces: parse: error"
      Just p -> return $ Spaces p

data PreSpace a = PreSpace
  { psSpaces :: Spaces
  , psData :: a
  } deriving (Eq, Ord, Show)

instance Functor PreSpace where
  fmap f (PreSpace s a) = PreSpace s (f a)

instance Renderable a => Renderable (PreSpace a) where
  render (PreSpace s d) = render s <> render d
  parse = liftM2 PreSpace parse parse
