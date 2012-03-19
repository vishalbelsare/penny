module PennyTest.Copper.Memos.Posting where

import Control.Applicative ((<$>), (*>), (<*))
import qualified Penny.Lincoln.Bits as B
import qualified Penny.Copper.Memos.Posting as P

import Test.QuickCheck (Gen, suchThat, arbitrary, listOf,
                        Arbitrary, arbitrary, sized, resize)
import PennyTest.Copper.Util (genTextNonEmpty)
import Test.Framework (Test, testGroup)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import qualified Text.Parsec as Parsec

-- | Generate renderable memos.
genRMemo :: Gen B.Memo
genRMemo =
  B.Memo
  <$> (sized $ \s -> resize (min 5 s) (listOf genRMemoLine))

genRMemoLine :: Gen B.MemoLine
genRMemoLine = B.MemoLine <$> genTextNonEmpty p p where
  p = suchThat arbitrary P.isCommentChar

newtype RMemo = RMemo B.Memo deriving (Eq, Show)
instance Arbitrary RMemo where
  arbitrary = RMemo <$> genRMemo

-- | Parsing rendered Memo should yield same Memo.
prop_parseRendered :: RMemo -> Bool
prop_parseRendered (RMemo m) = case P.render m of
  Nothing -> False
  Just t -> let
    parser = Parsec.many (Parsec.char ' ') *> P.memo <* Parsec.eof
    in case Parsec.parse parser "" t of
      Left _ -> False
      Right m' -> m == m'

test_parseRendered :: Test
test_parseRendered = testProperty s prop_parseRendered where
  s = "parsing rendered Memo yields same Memo"

tests :: Test
tests = testGroup "Posting"
        [ test_parseRendered ]
