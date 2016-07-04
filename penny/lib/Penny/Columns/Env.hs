{-# LANGUAGE TemplateHaskell #-}

module Penny.Columns.Env where

import Control.Lens (makeLenses)

import Penny.Clatch
import Penny.Colors
import Penny.Cursor
import Penny.Popularity

data Env = Env
  { _clatch :: Clatch (Maybe Cursor)
  , _history :: History
  , _colors :: Colors
  }

makeLenses ''Env