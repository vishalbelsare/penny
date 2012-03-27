module Penny.Zinc.Help where

import Data.Text (Text, pack)

help :: Text
help = pack $ unlines [
  "usage: zinc [posting filters] report [report options] file . . .",
  "",
  "Posting filters",
  "------------------------------------------",
  "",
  "Dates",
  "-----",
  "",
  "--date cmp timespec, -d cmp timespec",
  "  Date must be within the time frame given. timespec",
  "  is a day or a day and a time. Valid values for cmp:",
  "     <, >, <=, >=, ==, /=, !=",
  "--current",
  "  Same as \"--date <= (right now) \"",
  "",
  "Sequence numbers (see documentation)",
  "------------------------------------",
  "",
  "--fwd-seq-unsorted cmp num",
  "--back-seq-unsorted cmp num",
  "--fwd-seq-sorted cmp num",
  "--back-seq-sorted cmp num",
  "  Sequence number must fall within given range.",
  "",
  "Pattern matching",
  "----------------",
  "",
  "-a pattern, --account pattern",
  "  Pattern must match colon-separated account name",
  "--account-level num pat",
  "  Pattern must match sub account at given level",
  "--account-any pat",
  "  Pattern must match sub account at any level",
  "-p pattern, --payee pattern",
  "  Payee must match pattern",
  "-t pattern, --tag pattern",
  "  Tag must match pattern",
  "--number pattern",
  "  Number must match pattern",
  "--flag pattern",
  "  Flag must match pattern",
  "--commodity pattern",
  "  Pattern must match colon-separated commodity name",
  "--commodity-level num pattern",
  "  Pattern must match sub commodity at given level",
  "--commodity-any pattern",
  "  Pattern must match sub commodity at any level",
  "--posting-memo pattern",
  "  Posting memo must match pattern",
  "--transaction-memo pattern",
  "  Transaction memo must match pattern",
  "",
  "Other posting characteristics",
  "-----------------------------",
  "--debit",
  "  Entry must be a debit",
  "--credit",
  "  Entry must be a credit",
  "--qty cmp number",
  "  Entry quantity must fall within given range",
  "",
  "Operators - from highest to lowest precedence",
  "(all are left associative)",
  "--------------------------",
  "--open expr --close",
  "  Force precedence (as in \"open\" and \"close\" parentheses)",
  "--not expr",
  "  True if expr is false",
  "expr1 --and expr2 ",
  "  True if expr and expr2 are both true",
  "expr1 --or expr2",
  "  True if either expr1 or expr2 is true",
  "",
  "Options affecting patterns",
  "--------------------------",
  "",
  "-i, --case-insensitive",
  "  Be case insensitive (default)",
  "-I, --case-sensitive",
  "  Be case sensitive",
  "",
  "--within",
  "  Use \"within\" matcher (default)",
  "--pcre",
  "  Use \"pcre\" matcher",
  "--posix",
  "  Use \"posix\" matcher",
  "--exact",
  "  Use \"exact\" matcher",
  "",
  "Removing postings after sorting and filtering",
  "---------------------------------------------",
  "--head n",
  "  Keep only the first n postings",
  "--tail n",
  "  Keep only the last n postings",
  "",
  "Sorting",
  "-------",
  "",
  "-s key, --sort key",
  "  Sort postings according to key",
  "",
  "Keys:",
  "  payee, date, flag, number, account, drCr,",
  "  qty, commodity, postingMemo, transactionMemo",
  "",
  "  Ascending order by default; for descending order,",
  "  capitalize the name of the key.",
  ""
  ]
