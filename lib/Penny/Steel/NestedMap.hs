-- | A nested map. The values in each NestedMap are tuples, with the
-- first element of the tuple being a label that you select and the
-- second value being another NestedMap. Functions are provided so you
-- may query the map at any level or insert new labels (and,
-- therefore, new keys) at any level.
module Penny.Steel.NestedMap (
  NestedMap ( NestedMap, unNestedMap ),
  empty,
  relabel,
  descend,
  insert,
  cumulativeTotal,
  traverse,
  traverseWithTrail,
  toForest ) where

import Control.Applicative ((<*>), (<$>))
import Data.Map ( Map )
import qualified Data.Foldable as F
import qualified Data.Traversable as T
import qualified Data.Tree as E
import qualified Data.Map as M
import Data.Monoid ( Monoid, mconcat, mappend, mempty )

newtype NestedMap k l =
  NestedMap { unNestedMap :: Map k (l, NestedMap k l) }
  deriving (Eq, Show, Ord)

instance Functor (NestedMap k) where
  fmap f (NestedMap m) = let
    g (l, s) = (f l, fmap f s)
    in NestedMap $ M.map g m

instance (Ord k) => F.Foldable (NestedMap k) where
  foldMap = T.foldMapDefault

instance (Ord k) => T.Traversable (NestedMap k) where
  -- traverse :: Applicative f
  --          => (a -> f b)
  --          -> NestedMap k a
  --          -> f (NestedMap k b)
  traverse f (NestedMap m) = let
      f' (l, m') = (,) <$> f l <*> T.traverse f m'
      in NestedMap <$> T.traverse f' m

-- | An empty NestedMap.
empty :: NestedMap k l
empty = NestedMap (M.empty)

-- | Helper function for relabel. For a given key and function
-- that modifies the label, return the new submap to insert into the
-- given map. Does not actually insert the submap though. That way,
-- relabel can then modify the returned submap before
-- inserting it into the mother map with the given label.
newSubmap ::
  (Ord k)
  => NestedMap k l
  -> k
  -> (Maybe l -> l)
  -> (l, NestedMap k l)
newSubmap (NestedMap m) k g = (newL, NestedMap newM) where
  (newL, newM) = case M.lookup k m of
    Nothing -> (g Nothing, M.empty)
    (Just (oldL, (NestedMap oldM))) -> (g (Just oldL), oldM)

-- | Descends through a NestedMap with successive keys in the list,
-- proceeding from left to right. At any given level, if the key
-- given does not already exist, then inserts an empty submap and
-- applies the given label modification function to Nothing to
-- determine the new label. If the given key already does exist, then
-- preserves the existing submap and applies the given label
-- modification function to (Just oldlabel) to determine the new
-- label.
relabel ::
  (Ord k)
  => NestedMap k l
  -> [(k, (Maybe l -> l))]
  -> NestedMap k l
relabel m [] = m
relabel (NestedMap m) ((k, f):vs) = let
  (newL, newM) = newSubmap (NestedMap m) k f
  newM' = relabel newM vs
  in NestedMap $ M.insert k (newL, newM') m

-- | Given a list of keys, find the key that is furthest down in the
-- map that matches the requested list of keys. Returns [(k, l)],
-- where the first item in the list is the topmost key found and its
-- matching label, and the last item in the list is the deepest key
-- found and its matching label. (Often you will be most interested
-- in the deepest key.)
descend ::
  Ord k
  => [k]
  -> NestedMap k l
  -> [(k, l)]
descend keys (NestedMap mi) = descend' keys mi where
  descend' [] _ = []
  descend' (k:ks) m = case M.lookup k m of
    Nothing -> []
    Just (l, (NestedMap im)) -> (k, l) : descend' ks im


-- | Descends through the NestedMap one level at a time, proceeding
-- key by key from left to right through the list of keys given. At
-- the last key, appends the given label to the labels already
-- present; if no label is present, uses mempty and mappend to create
-- a new label. If the list of keys is empty, does nothing.
insert ::
  (Ord k, Monoid l)
  => NestedMap k l
  -> [k]
  -> l
  -> NestedMap k l
insert m [] _ = m
insert m ks l = relabel m ts where
  ts = firsts ++ [end]
  firsts = map (\k -> (k, keepOld)) (init ks) where
    keepOld mk = case mk of
      (Just old) -> old
      Nothing -> mempty
  end = (key, newL) where
    key = last ks
    newL mk = case mk of
      (Just old) -> old `mappend` l
      Nothing -> mempty `mappend` l

totalMap ::
  (Monoid l)
  => NestedMap k l
  -> l
totalMap (NestedMap m) =
  if M.null m
  then mempty
  else mconcat . map totalTuple . M.elems $ m

totalTuple ::
  (Monoid l)
  => (l, NestedMap k l)
  -> l
totalTuple (l, (NestedMap top)) =
  if M.null top
  then l
  else mappend l (totalMap (NestedMap top))

remapWithTotals ::
  (Monoid l)
  => NestedMap k l
  -> NestedMap k l
remapWithTotals (NestedMap top) =
  if M.null top
  then NestedMap M.empty
  else NestedMap $ M.map f top where
    f a@(_, m) = (totalTuple a, remapWithTotals m)

-- | Leaves all keys of the map and submaps the same. Changes each
-- label to reflect the total of that label and of all the labels of
-- the maps within the NestedMap accompanying the label. Returns the
-- total of the entire NestedMap.
cumulativeTotal ::
  (Monoid l)
  => NestedMap k l
  -> (l, NestedMap k l)
cumulativeTotal m = (totalMap m, remapWithTotals m)

-- | Supply a function that takes a key, a label, and a
-- NestedMap. traverse will traverse the NestedMap. For each (label,
-- NestedMap) pair, traverse will first apply the given function to
-- the label before descending through the NestedMap. The function is
-- applied to the present key and label and the accompanying
-- NestedMap. The function you supply must return a Maybe. If the
-- result is Nothing, then the pair is deleted as a value from its
-- parent NestedMap. If the result is (Just s), then the label of this
-- level of the NestedMap is changed to s before descending to the
-- next level of the NestedMap.
--
-- All this is done in a monad, so you can carry out arbitrary side
-- effects such as inspecting or changing a state or doing IO. If you
-- don't need a monad, just use Identity.
--
-- Thus this function can be used to inspect, modify, and prune a
-- NestedMap.
--
-- For a simpler traverse that does not provide you with so much
-- information, NestedMap is also an instance of Data.Traversable.
traverse ::
  (Monad m, Ord k)
  => (k -> l -> NestedMap k l -> m (Maybe a))
  -> NestedMap k l
  -> m (NestedMap k a)
traverse f m = traverseWithTrail (\_ -> f) m

-- | Like traverse, but the supplied function is also applied to a
-- list that tells it about the levels of NestedMap that are parents
-- to this NestedMap.
traverseWithTrail ::
  (Monad m, Ord k)
  => ( [(k, l)] -> k -> l -> NestedMap k l -> m (Maybe a) )
  -> NestedMap k l
  -> m (NestedMap k a)
traverseWithTrail f = traverseWithTrail' f []

traverseWithTrail' ::
  (Monad m, Ord k)
  => ([(k, l)] -> k -> l -> NestedMap k l -> m (Maybe a))
  -> [(k, l)]
  -> NestedMap k l
  -> m (NestedMap k a)
traverseWithTrail' f ts (NestedMap m) =
  if M.null m
  then return $ NestedMap M.empty
  else do
    let ps = M.assocs m
    mlsMaybes <- mapM (traversePairWithTrail f ts) ps
    let ps' = zip (M.keys m) mlsMaybes
        folder (k, ma) rs = case ma of
          (Just r) -> (k, r):rs
          Nothing -> rs
        ps'' = foldr folder [] ps'
    return (NestedMap (M.fromList ps''))

traversePairWithTrail ::
  (Monad m, Ord k)
  => ( [(k, l)] -> k -> l -> NestedMap k l -> m (Maybe a) )
  -> [(k, l)]
  -> (k, (l, NestedMap k l))
  -> m (Maybe (a, NestedMap k a))
traversePairWithTrail f ls (k, (l, m)) = do
  ma <- f ls k l m
  case ma of
    Nothing -> return Nothing
    (Just a) -> do
      m' <- traverseWithTrail' f ((k, l):ls) m
      return (Just (a, m'))

-- | Convert a NestedMap to a Forest.
toForest :: Ord k => NestedMap k l -> E.Forest (k, l)
toForest = map toNode . M.assocs . unNestedMap
  where
    toNode (k, (l, m)) = E.Node (k, l) (toForest m)

-- For testing
_new :: (k, l) -> (k, (Maybe l -> l))
_new (k, l) = (k, const l)

_map1, _map2, _map3, _map4 :: NestedMap Int String
_map1 = NestedMap M.empty
_map2 = relabel _map1 [_new (5, "hello"), _new (66, "goodbye"), _new (777, "yeah")]
_map3 = relabel _map2 [_new (6, "what"), _new (77, "zeke"), _new (888, "foo")]
_map4 = relabel _map3
       [ (6, (\m -> case m of Nothing -> "_new"; (Just s) -> s ++ "_new"))
       , (77, (\m -> case m of Nothing -> "_new"; (Just s) -> s ++ "more _new")) ]

_printer :: Int -> String -> a -> IO (Maybe ())
_printer i s _ = do
  putStrLn (show i)
  putStrLn s
  return $ Just ()

_printerWithTrail :: [(Int, String)] -> Int -> String -> a -> IO (Maybe ())
_printerWithTrail ps n str _ = do
  let ptr (i, s) = putStr ("(" ++ show i ++ ", " ++ s ++ ") ")
  mapM_ ptr . reverse $ ps
  ptr (n, str)
  putStrLn ""
  return $ Just ()

_showMap4 :: IO ()
_showMap4 = do
  _ <- traverse _printer _map4
  return ()

_showMapWithTrail :: IO ()
_showMapWithTrail = do
  _ <- traverseWithTrail _printerWithTrail _map4
  return ()