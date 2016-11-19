{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE BangPatterns #-}
-- | Copper - the default Penny parser
--
-- Copper runs in three phases.  The first phase transforms a string
-- into an abstract syntax tree, or AST.  It uses the Earley library
-- do this.  The grammar, in "Penny.Copper.Types", is a context-free
-- grammar created in "Penny.Copper.Grammar".
-- Most error handling occurs within this
-- grammar itself--that is, the grammar is meticulously written so
-- that invalid constructs are not valid in the grammar.
--
-- The grammar does a remarkable amount of work: it ensures the
-- correctness of all dates (even leap days).  It constrains number
-- representations to permissible forms (even ensuring that grouping
-- constructs are valid--for instance, you cannot have two grouping
-- characters in a row.)  It ensures that if the user enters a side
-- (Debit, using @<@, or Credit, using @>@) that she does not enter
-- a number representation that is zero.
--
-- The second phase transforms this AST into the data types that are
-- used in the rest of Penny.  This is called @decopperization@ and is in
-- "Penny.Copper.Decopperize".
--
-- The third phase performs final error checking.  It ensures that
-- postings are valid, that transactions are balanced, and that
-- prices are valid.  This phase is called the @proofer@ and it is
-- in "Penny.Copper.Proofer".
--
-- This module contains the functions that most of the rest of the
-- library would ordinarily need.
module Penny.Copper where

import Accuerr (Accuerr)
import qualified Accuerr
import Control.Exception (Exception)
import qualified Control.Exception as Exc
import qualified Control.Lens as Lens
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Sequence.NonEmpty (NonEmptySeq)
import qualified Data.Sequence.NonEmpty as NE
import Data.Sums (S3(S3a, S3b, S3c))
import Data.Text (Text)
import qualified Data.Text as X
import Data.Typeable (Typeable)
import qualified Text.Earley as Earley
import Pinchot (Loc(Loc))
import qualified Pinchot

import Penny.Copper.Copperize (TracompriError, tracompriWholeFile)
import Penny.Copper.Decopperize
import qualified Penny.Copper.EarleyGrammar as EarleyGrammar
import Penny.Copper.Formatter (formatWholeFile)
import qualified Penny.Copper.Productions as Productions
import qualified Penny.Copper.Proofer as Proofer
import Penny.Copper.Types (WholeFile)
import Penny.Copper.Tracompri
import Penny.Cursor
import Penny.Unix

-- | Given an integer position in a text, obtain the Pinchot
-- position.
textPosition
  :: Int
  -- ^ Integer position (0-based, from Earley)
  -> Text
  -> Loc
textPosition int
  = X.foldl' add (Loc 1 1 1)
  . X.take int
  where
    add (Loc !lin !col !pos) c
      | c == '\n' = Loc (lin + 1) 1 (pos + 1)
      | c == '\t' = Loc lin (col + 8 - ((col - 1) `mod` 8)) (pos + 1)
      | otherwise = Loc lin (col + 1) (pos + 1)

-- | The name of a file being parsed.  This is optional and can be
-- the empty 'Text'.
type Filename = Text

-- | Gives additional information when an Earley parse fails.
data ParseErrorInfo = ParseErrorInfo
  { _failurePosition :: Loc
  , _expected :: [String]
  } deriving (Typeable, Show)

Lens.makeLenses ''ParseErrorInfo

-- | An Earley parse can fail either because the entire input was not
-- parsed, or because the parse aborted.
data ParseFailReason
  = LeftoverInput
  | AbortedParse
  deriving (Typeable, Show)

Lens.makePrisms ''ParseFailReason

-- | An Earley parse failure.  Contains the reason for the failure,
-- and information about where the failure occurred and the expected
-- productions at the point of failure.
data ParseError = ParseError
  { _parseFailReason :: ParseFailReason
  , _parseErrorInfo :: ParseErrorInfo
  } deriving (Typeable, Show)

Lens.makeLenses ''ParseError

-- | Creates a 'ParseErrorInfo'.
errorInfo
  :: Text
  -- ^ Input text
  -> Earley.Report String a
  -> ParseErrorInfo
errorInfo inp (Earley.Report pos exp _)
  = ParseErrorInfo (textPosition pos inp) exp

-- | Parses a particular production from
-- 'Penny.Copper.Productions.Productions'.  Applies 'error' if the
-- grammar is ambiguous.
parseProduction
  :: (forall r. Productions.Productions r Char Loc
      -> Earley.Prod r String (Char, Loc) (p Char Loc))
  -- ^ Earley grammar to parse
  -> Text
  -- ^ Input string
  -> Either ParseError (p Char Loc)
parseProduction getGrammar txt = case results of
  result:[]
    | Seq.null (Earley.unconsumed report) -> Right result
    | otherwise -> Left (ParseError LeftoverInput info)
  [] -> Left (ParseError AbortedParse info)
  _ -> error "parseProduction: grammar is ambiguous."
  where
    (results, report) = Pinchot.locatedFullParses grammar txt
    grammar = fmap getGrammar EarleyGrammar.earleyGrammar
    info = errorInfo txt report

-- | A parse-convert-proof sequence can fail if parsing, collection,
-- or validation fails.  (Decopperization never fails.)
data ParseConvertProofError a = ParseConvertProofError
  { _pcpFilename :: InputFilespec
  , _pcpFailure
      :: S3 ParseError (NonEmptySeq (Proofer.CollectionFail a))
                       (NonEmptySeq (Proofer.ValidationFail a))
  } deriving (Typeable, Show)

Lens.makeLenses ''ParseConvertProofError

instance (Typeable a, Show a) => Exception (ParseConvertProofError a)

parseWholeFile
  :: InputFilespec
  -- ^
  -> Text
  -- ^
  -> Either (ParseConvertProofError Loc) (WholeFile Char Loc)
parseWholeFile fn
  = Lens.over Lens._Left (ParseConvertProofError fn . S3a)
  . parseProduction Productions.a'WholeFile

proofWholeFile
  :: InputFilespec
  -- ^
  -> WholeFile Char Loc
  -- ^
  -> Either (ParseConvertProofError Loc) (Seq (Tracompri Cursor))
proofWholeFile fn
  = Lens.over Lens._Left convertError
  . Lens.over Lens._Right convertSuccess
  . Proofer.proofItems
  . dWholeFile
  where
    convertError (Left collectionFails) = ParseConvertProofError fn
      (S3b collectionFails)
    convertError (Right validationFails) = ParseConvertProofError fn
      (S3c validationFails)
    convertSuccess = fmap (fmap (Cursor fn))

-- | Takes the result of parsing a production and returns either the
-- result or a ParseConvertProofError.
parseResultToError
  :: InputFilespec
  -- ^
  -> Either ParseError (p Char Loc)
  -- ^
  -> Either (ParseConvertProofError a) (p Char Loc)
parseResultToError filename
  = Lens.over Lens._Left (ParseConvertProofError filename . S3a)


-- | Takes the result of proofing items and returns either the result
-- or a ParseConvertProofError.
proofResultToError
  :: Traversable t
  => InputFilespec
  -- ^
  -> Proofer.Proofer Loc (t (Tracompri Loc))
  -- ^
  -> Either (ParseConvertProofError Loc) (t (Tracompri Cursor))
proofResultToError filename proofer = case proofer of
  Left (Left collectionFails) ->
    Left (ParseConvertProofError filename (S3b collectionFails))
  Left (Right validationFails) ->
    Left (ParseConvertProofError filename (S3c validationFails))
  Right g -> Right . fmap (fmap (Cursor filename)) $ g

-- | Parses, converts, and proofs a single file.
parseConvertProof
  :: (InputFilespec, Text)
  -- ^ Name and data of file
  -> Either (ParseConvertProofError Loc) (Seq (Tracompri Cursor))
parseConvertProof (filename, txt) = do
  wholeFile <- parseResultToError filename
    $ parseProduction Productions.a'WholeFile txt
  proofResultToError filename . Proofer.proofItems . dWholeFile
    $ wholeFile

-- | Parses, converts, and proofs a series of files.
parseConvertProofFiles
  :: Traversable t
  => t (InputFilespec, Text)
  -- ^ Sequence of filenames to parse, with their accompanying text
  -> Accuerr (NonEmptySeq (ParseConvertProofError Loc))
             (t (Seq (Tracompri Cursor)))
  -- ^ If this fails, there will be at least one
  -- 'ParseConvertProofError'.
parseConvertProofFiles
  = traverse
  $ Lens.over Accuerr._AccFailure NE.singleton
  . Accuerr.eitherToAccuerr
  . parseConvertProof

-- * Formatting Tracompri

-- | Transforms 'Tracompri' into a 'WholeFile', and applies some
-- simple default formatting.
copperizeAndFormat
  :: Seq (Tracompri a)
  -> Accuerr (NonEmptySeq (TracompriError a)) (WholeFile Char ())
copperizeAndFormat
  = fmap (formatWholeFile 4)
  . tracompriWholeFile

-- * IO functions

newtype ParseConvertProofErrors
  = ParseConvertProofErrors (NonEmptySeq (ParseConvertProofError Loc))
  deriving (Typeable, Show)

instance Exception ParseConvertProofErrors

-- | Parses, converts, and proofs a sequence of filenames.  Any errors
-- are thrown as exceptions.
parseConvertProofIO
  :: Seq Text
  -> IO (NonEmptySeq (Seq (Tracompri Cursor)))
parseConvertProofIO files = do
  filesAndTexts <- readCommandLineFiles files
  case parseConvertProofFiles filesAndTexts of
    Accuerr.AccFailure errs -> Exc.throwIO (ParseConvertProofErrors errs)
    Accuerr.AccSuccess g -> return g
