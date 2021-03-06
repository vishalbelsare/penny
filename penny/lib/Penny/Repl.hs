{-# LANGUAGE OverloadedStrings, OverloadedLists #-}
-- | For use in a REPL.
--
-- Merely by doing an
--
-- > :set -XOverloadedStrings -XOverloadedLists
-- > import Penny.Repl
--
-- the user should be able to do common tasks in the REPL.  This
-- module will do whatever re-exports are necessary to make this
-- happen.
--
-- Also, the Haddocks for this module must be readable, so keep this
-- in mind when re-exporting other functions and modules.

module Penny.Repl
  (

  -- * Number types
    Exponential
  , DecUnsigned

  -- * Data types
  , Text
  , SubAccount
  , Seq
  , Account
  , Commodity
  , Pole

  -- ** Serials
  , Serset
  , forward
  , backward

  -- ** Time and date types
  , Time.ZonedTime
  , Time.Day
  , Time.TimeOfDay
  , Time.TimeZone

  -- * Clatcher types
  , Clatcher
  , Loader
  , Report

  -- * Quasi quoters
  , qDay
  , qTime
  , qUnsigned
  , qNonNeg

  -- * Loading files
  , copopen
  , load

  -- * Converting commodities
  , Converter
  , convert
  , converter

  -- * Filtering
  , prefilt
  , postfilt

  -- * Sorting
  , sort
  , comparing

  -- * Reports
  -- ** Dump
  , Dump.dump

  -- ** Columns
  , Column
  , Columns
  , checkbook
  , table

  -- ** Acctree
  , acctree
  , byQty
  , bySubAccountCmp
  , bySubAccount

  -- ** Pctree
  , pctree
  , Penny.Polar.debit
  , Penny.Polar.credit

  -- * Output
  , Colors
  , colors
  , light
  , dark
  , report

  -- * Running the clatcher
  , clatcher
  , presets

  -- * Accessing fields
  -- ** Transaction fields
  , zonedTime
  , day
  , timeOfDay
  , timeZone
  , timeZoneMinutes
  , payee

  -- ** Posting fields
  , birth
  , number
  , flag
  , account
  , fitid
  , tags
  , commodity
  , AP.reconciled
  , AP.cleared
  , AP.side
  , AP.qty
  , AP.magnitude
  , AP.isDebit
  , AP.isCredit
  , AP.isZero

  -- * Comparison helpers
  , NonNegative
  , cmpUnsigned
  , (&&&)
  , (|||)

  -- * Lens operators
  , (&)
  , (.~)
  , (^.)

  -- * Monoid operators
  , (<>)

  -- * Time
  , zonedTimeToUTC

  ) where

import Penny.Account
import Penny.Acctree
import Penny.BalanceMap
import Penny.Commodity
import qualified Penny.Clatch.Access.Posting as AP
import qualified Penny.Clatch.Access.TransactionX as AT
import Penny.Clatch.Types
import Penny.Clatcher
import Penny.Colors
import Penny.Table (Column, Columns, checkbook, table)
import Penny.Converter
import Penny.Copper (copopen)
import Penny.Decimal
import qualified Penny.Dump as Dump
import Penny.NonNegative
import Penny.Pctree
import Penny.Polar
import Penny.Quasi
import Penny.Report
import Penny.Serial (Serset)
import qualified Penny.Serial as Serial
import Penny.Unix

import Control.Lens (view, (&), (.~), (^.))
import Data.Foldable (toList)
import Data.Monoid ((<>))
import Data.Ord (comparing)
import Data.Sequence (Seq)
import Data.Text (Text)
import Data.Time (zonedTimeToUTC)
import qualified Data.Time as Time
import Turtle.Bytes (procs)
import Turtle.Shell (select)
import Rainbow (chunksToByteStrings, toByteStringsColors256)

-- | Runs the clatcher with the specified settings.  Sends output to
-- @less@ with 256 colors.
clatcher :: Clatcher -> IO ()
clatcher cltch = do
  chks <- runClatcher cltch
  procs "less" lessOpts
    (select . chunksToByteStrings toByteStringsColors256
      . toList $ chks)

-- | A set of reasonable presets:
--
-- * Colorful output is sent to @less@
--
-- * the light color scheme is used
--
-- * the checkbook column report is used
--
-- * postings are sorted by date and time, after converting the zoned
-- time to UTC time
presets :: Clatcher
presets = mempty
  & colors .~ light
  & report .~ table checkbook
  & sort   .~ comparing (zonedTimeToUTC . zonedTime)

-- # Helpers

-- | A point-free version of '&&'.

(&&&) :: (a -> Bool) -> (a -> Bool) -> a -> Bool
l &&& r = \a -> l a && r a
infixr 3 &&&

-- | A point-free version of '||'.
(|||) :: (a -> Bool) -> (a -> Bool) -> a -> Bool
l ||| r = \a -> l a || r a
infixr 2 |||

-- # Accessing fields

-- ## Transaction fields

zonedTime :: Sliced l a -> Time.ZonedTime
zonedTime = view AT.zonedTime

day :: Sliced l a -> Time.Day
day = view AT.day

timeOfDay :: Sliced l a -> Time.TimeOfDay
timeOfDay = view AT.timeOfDay

timeZone :: Sliced l a -> Time.TimeZone
timeZone = view AT.timeZone

timeZoneMinutes :: Sliced l a -> Int
timeZoneMinutes = view AT.timeZoneMinutes

payee :: Sliced l a -> Text
payee = view AT.payee

-- ## Posting fields

-- | How this single posting relates to its sibling postings; that is,
-- its \"birth order\".  Numbering restarts with every transaction.
birth :: Sliced l a -> Serset
birth = view AP.birth

-- | A number assigned by the user.
number :: Sliced l a -> Maybe Integer
number = view AP.number

flag :: Sliced l a -> Text
flag = view AP.flag

account :: Sliced l a -> Account
account = view AP.account

-- | Financial institution ID; often provided in OFX files.
fitid :: Sliced l a -> Text
fitid = view AP.fitid

-- | List of tags assigned by the user.
tags :: Sliced l a -> Seq Text
tags = view AP.tags

-- | The commodity of this posting.
commodity :: Sliced l a -> Text
commodity = view AP.commodity

-- # Functions to access 'Serset' components.

forward :: Serset -> NonNegative
forward = view Serial.forward

backward :: Serset -> NonNegative
backward = view Serial.backward
