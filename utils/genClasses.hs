module Main where

fileData :: String -> [String]
fileData = filter (not . bad) . lines
  where
    bad s = null s || head s == '#'

classesKind0 :: String -> [String]
classesKind0 s =
  [ "instance Parseable " ++ s ++ " where parser = p" ++ s
  , "instance Renderable " ++ s ++ " where render = r" ++ s
  , ""
  ]

classesGroupOnly :: String -> [String]
classesGroupOnly s =
  [ "instance ParseableG " ++ s ++ " where parserG = p" ++ s
  , "instance RenderableG " ++ s ++ " where renderG = r" ++ s
  , ""
  ]

classesRadixAndGrouper :: String -> [String]
classesRadixAndGrouper s =
  [ "instance ParseableRG " ++ s ++ " where parserRG = p" ++ s
  , "instance RenderableRG " ++ s ++ " where renderRG = r" ++ s
  , ""
  ]

classesRadixOnly :: String -> [String]
classesRadixOnly s =
  [ "instance ParseableR " ++ s ++ " where parserR = p" ++ s
  , "instance RenderableR " ++ s ++ " where renderR = r" ++ s
  , ""
  ]

output :: (String -> [String]) -> String -> IO ()
output printer fn = do
  txt <- fmap fileData . readFile $ fn
  mapM putStrLn . concat . map printer $ txt
  return ()

main :: IO ()
main = do
  output classesKind0 "kind0"
  output classesGroupOnly "grouperOnly"
  output classesRadixAndGrouper "radixAndGrouper"
  output classesRadixOnly "radixOnly"
