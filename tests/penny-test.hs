{-# OPTIONS_GHC -fno-warn-unused-imports #-}
-- This module generated by the genTests.hs program.
module Main where

import qualified Deka.Dec.Generators
import qualified Deka.Native.Abstract.Generators
import qualified Penny.Lincoln.Decimal.Frac.Generators
import qualified Penny.Lincoln.Decimal.Lane.Generators
import qualified Penny.Lincoln.Decimal.Masuno.Generators
import qualified Penny.Lincoln.Decimal.Side.Generators
import qualified Penny.Lincoln.Natural.Generators
import qualified Test.Tasty

testTree :: Test.Tasty.TestTree
testTree = Test.Tasty.testGroup "All tests"
  []

main :: IO ()
main = Test.Tasty.defaultMain testTree
