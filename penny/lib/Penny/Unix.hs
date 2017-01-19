{-# LANGUAGE OverloadedStrings #-}
-- | Functions useful when writing Unix command-line programs.
module Penny.Unix where

import Control.Monad.IO.Class (MonadIO)
import Data.Sequence (Seq)
import Data.Sequence.NonEmpty (NonEmptySeq)
import qualified Data.Sequence.NonEmpty as NE
import Data.Text (Text)
import qualified Data.Text as X
import qualified Data.Text.IO as XIO
import qualified System.Environment as Env
import qualified System.Exit as Exit
import qualified System.IO as IO
import qualified Turtle

import Penny.Cursor

-- | Reads a sequence of string filenames into texts.  If there is no
-- file, or a file is a @-@, reads standard input.
readFileListStdinIfEmpty
  :: Seq Text
  -- ^ Files to read
  -> IO (NonEmptySeq (InputFilespec, Text))
readFileListStdinIfEmpty files = case NE.seqToNonEmptySeq files of
  Nothing -> do
    x <- XIO.getContents
    return (NE.singleton (Stdin, x))
  Just neFiles -> traverse readCommandLineFile neFiles


-- | Reads a sequence of string filenames into texts.  If a file is
-- @-@, reads standard input for that file.  Does NOT read standard
-- input if the input list is empty.
readFileList
  :: Seq Text
  -- ^ Files to read
  -> IO (Seq (InputFilespec, Text))
readFileList = traverse readCommandLineFile

readCommandLineFile :: Text -> IO (InputFilespec, Text)
readCommandLineFile fn
  | fn == "-" = do
      x <- XIO.getContents
      return (Stdin, x)
  | otherwise = do
      x <- XIO.readFile (X.unpack fn)
      return (GivenFilename fn, x)

readMaybeCommandLineFile :: Maybe Text -> IO (InputFilespec, Text)
readMaybeCommandLineFile = readCommandLineFile . maybe "-" id

-- | Prints the error message, then exits.
errorFail :: String -> IO a
errorFail str = do
  pn <- Env.getProgName
  IO.hPutStrLn IO.stderr $ pn ++ ": error: " ++ str
  Exit.exitFailure

-- | Does something that might fail.  If it fails, show the failure,
-- and exit.  If it succeeds, return the successful thing.
errorExit :: Show e => Either e a -> IO a
errorExit ei = case ei of
  Left e -> errorFail . show $ e
  Right g -> return g


-- | Generic options for @less@.
lessOpts :: [Text]
lessOpts = ["--RAW-CONTROL-CHARS", "--chop-long-lines"]

-- | Runs @less@ in a subprocess with @lessOpts@.  Throws
-- 'Turtle.ProcFailed' for non-zero exit codes.
less
  :: MonadIO io
  => Turtle.Shell Turtle.Line
  -> io ()
less = Turtle.procs "less" lessOpts

-- | Converts an 'IO' 'Text' to a 'Turtle.Shell' 'Turtle.Line'.
ioTextToShell :: IO Text -> Turtle.Shell Turtle.Line
ioTextToShell io = do
  text <- Turtle.liftIO io
  let lines = Turtle.textToLines text
  Turtle.select lines

-- | Converts a 'Text' to a 'Turtle.Shell' 'Turtle.Line'.
textToShell :: Text -> Turtle.Shell Turtle.Line
textToShell = Turtle.select . Turtle.textToLines