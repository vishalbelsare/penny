{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NoImplicitPrelude #-}
-- | Given an OFX file, change every matching posting that does not
-- currently have a flag to Cleared.  Results are printed to standard
-- output.
module Penny.Clearer where

import qualified Accuerr
import qualified Control.Exception as Exception
import qualified Control.Lens as Lens
import qualified Data.OFX as OFX
import qualified Data.Set as Set
import qualified Data.Text as X

import Penny.Account
import Penny.Copper
import Penny.Copper.Terminalizers (t'WholeFile)
import Penny.Copper.Tracompri
import Penny.Cursor
import Penny.Fields
import Penny.Prelude
import Penny.Tranche (fields)
import Penny.Transaction
import Penny.Unix.Diff

-- | Clears the given file.  Returns the result as the output from @diff@.
clearer
  :: (Account -> Bool)
  -- ^ Clear accounts that match this predicate
  -> FilePath
  -- ^ Read this Copper file
  -> FilePath
  -- ^ Read this OFX file
  -> IO Patch
  -- ^ Returns the output from @diff@.
clearer acct copperFilename ofxFilename
  = clearedText acct copperFilename ofxFilename
  >>= diff copperFilename

clearedText
  :: (Account -> Bool)
  -- ^ Clear accounts that match this predicate
  -> FilePath
  -- ^ Read this Copper file
  -> FilePath
  -- ^ Read this OFX file
  -> IO Text
  -- ^ Returns the cleared text.
clearedText acct copperFilename ofxFilename = do
  ofxTxt <- readFile ofxFilename
  copperInput <- readFile copperFilename
  tracompris <- either Exception.throwIO return $ clearFile acct ofxTxt
    (Right copperFilename, copperInput)
  formatted <- either throwIO return
    . Accuerr.accuerrToEither . copperizeAndFormat
    $ tracompris
  return . X.pack . toList . fmap fst . t'WholeFile $ formatted

data ClearerFailure
  = ParseConvertProofFailed (ParseConvertProofError Loc)
  | OfxImportFailed Text
  deriving Show

instance Exception.Exception ClearerFailure

-- | Given the input OFX file and the input Penny file, create the result.
clearFile
  :: (Account -> Bool)
  -- ^ Clear a posting only if its account matches this predicate
  -> Text
  -- ^ OFX file
  -> (Either Text FilePath, Text)
  -- ^ Copper file
  -> Either ClearerFailure (Seq (Tracompri Cursor))
clearFile acct ofxTxt copperInput = do
  tracompris <- Lens.over Lens._Left ParseConvertProofFailed
    . parseConvertProof $ copperInput
  ofxTxns <- Lens.over Lens._Left (OfxImportFailed . pack)
    . OFX.parseTransactions . X.unpack $ ofxTxt
  let fitids = allFitids ofxTxns
  return (Lens.over traversePostingFields (clearPosting acct fitids) tracompris)

-- | Gets a set of all fitid from a set of OFX transactions.
allFitids
  :: [OFX.Transaction]
  -> Set Text
allFitids = foldr g Set.empty
  where
    g txn = Set.insert (X.pack $ OFX.txFITID txn)

-- | Given a single posting and a set of all fitid, modify the posting
-- to Cleared if it currently does not have a flag.
clearPosting
  :: (Account -> Bool)
  -- ^ Only clear the posting if its account matches this predicate.
  -> Set Text
  -- ^ All fitid.  Clear the posting only if its fitid is in this set.
  -> PostingFields
  -> PostingFields
clearPosting acct fitids pf
  | acctMatches && fitIdFound && noCurrentFlag = Lens.set flag "C" pf
  | otherwise = pf
  where
    acctMatches = acct $ Lens.view account pf
    fitIdFound = Set.member (Lens.view fitid pf) fitids
    noCurrentFlag = Lens.view flag pf == ""

traversePostingFields
  :: Lens.Traversal' (Seq (Tracompri a)) PostingFields
traversePostingFields
  = traverse
  . _Tracompri'Transaction
  . postings
  . traverse
  . fields
