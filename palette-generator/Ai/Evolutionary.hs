{-# LANGUAGE MultiParamTypeClasses #-}

module Ai.Evolutionary ( EvolutionConfig(..), Species(..), evolve ) where

import Control.Applicative ( liftA2 )
import Data.Bifunctor ( second )
import Data.List ( mapAccumR, sortBy )
import Data.Ord ( Down(Down), comparing )
import System.Random ( RandomGen, randomR )

{- |
Find every possible combination of two values, with the first value
coming from one list and the second value coming from a different list.
-}
cartesianProduct :: [a] -> [b] -> [(a, b)]
cartesianProduct = liftA2 (,)

{- |
Find every possible combination of two values, with both values coming
from the same list. Values are allowed to be paired with themself.
-}
cartesianSquare :: [a] -> [(a, a)]
cartesianSquare as = as `cartesianProduct` as

-- | Chain a function a set number of times.
repeatCall :: Int -> (a -> a) -> a -> a
repeatCall n f = (!! n) . iterate f

-- | Pick a random element from a list using a random generator.
randomFromList :: (RandomGen r) => r -> [a] -> (a, r)
randomFromList generator list
  = let (index, generator') = randomR (0, length list - 1) generator
     in (list !! index, generator')

{- |
Map over a list, passing a random generator into the mapped
function each time it is called. A random generator is returned
along with the new list.
-}
mapWithGen :: (r -> a -> (r, b)) -> (r, [a]) -> (r, [b])
mapWithGen = uncurry . mapAccumR

unfoldWithGen :: (r -> (r, a)) -> Int -> r -> (r, [a])
unfoldWithGen _ 0 generator = (generator, [])
unfoldWithGen f size generator =
  let (generator', as) = unfoldWithGen f (size - 1) generator
      (generator'', a) = f generator'
   in (generator'', a:as)

{- |
A genotype is a value which is generated by the genetic algorithm.

The environment is used to specify the problem for which
we are trying to find the optimal genotype.
-}
class Species environment genotype where
  -- | Generate a new genotype at random.
  generate :: (RandomGen r) => environment -> r -> (r, genotype)

  -- | Randomly combine two genotypes.
  crossover :: (RandomGen r) => environment -> r -> genotype -> genotype -> (r, genotype)

  -- | Randomly mutate a genotype using the given environment.
  mutate :: (RandomGen r) => environment -> r -> genotype -> (r, genotype)

  -- | Score a genotype. Higher numbers are better.
  fitness :: environment -> genotype -> Double

-- | Parameters for the genetic algorithm.
data EvolutionConfig = EvolutionConfig
  { -- | The number of genotypes processed on each pass.
    populationSize :: Int,
    -- | How many genotypes make it through to the next pass.
    survivors :: Int,
    -- | The chance of a genotype being randomly changed
    --   before crossover. Between 0 and 1.
    mutationProbability :: Double,
    -- | Number of passes of the algorithm.
    generations :: Int
  }

{- |
Randomly mutate the given genotype, if the mutation probability
from the 'EvolutionConfig' says yes.
-}
randomMutation :: (RandomGen r, Species e g)
               => e -- ^ Environment
               -> EvolutionConfig
               -> r -- ^ Random generator
               -> g -- ^ Genotype to mutate
               -> (r, g)
randomMutation environment config generator chromosome
  = let (r, generator') = randomR (0.0, 1.0) generator
     in if r <= mutationProbability config
        then mutate environment generator' chromosome
        else (generator', chromosome)

{- |
Select the fittest survivors from a population,
to be moved to the next pass of the algorithm.
-}
naturalSelection :: (Species e g)
                 => e -- ^ Environment
                 -> EvolutionConfig
                 -> [g] -- ^ Original population
                 -> [g] -- ^ Survivors
naturalSelection environment config
  = map snd
  . take (survivors config)
  . sortBy (comparing fst)
  -- Avoid computing fitness multiple times during sorting
  -- Down reverses the sort order so that the best fitness comes first
  . map (\genotype -> (Down $ fitness environment genotype, genotype))

-- | Run one pass of the genetic algorithm over a given population.
evolveGeneration :: (RandomGen r, Species e g)
                 => e -- ^ Environment
                 -> EvolutionConfig
                 -> (r, [g]) -- ^ Random generator, original population
                 -> (r, [g]) -- ^ New random generator, new population
evolveGeneration environment config (generator, population)
  = second (naturalSelection environment config)
  $ mapWithGen (randomMutation environment config)
  $ unfoldWithGen randomCrossover (populationSize config) generator
    where pairs = cartesianSquare population
          randomCrossover gen = let (pair, gen') = randomFromList gen pairs
                                 in (uncurry $ crossover environment gen') pair

{- |
Create the initial population, to be fed into the first
pass of the genetic algorithm.
-}
initialGeneration :: (RandomGen r, Species e g)
                  => e -- ^ Environment
                  -> EvolutionConfig
                  -> r -- ^ Random generator
                 -> (r, [g]) -- ^ New random generator, population
initialGeneration environment config
  = unfoldWithGen (generate environment) (survivors config)

-- | Run the full genetic algorithm.
evolve :: (RandomGen r, Species e g)
       => e -- ^ Environment
       -> EvolutionConfig
       -> r -- ^ Random generator
       -> (r, g) -- ^ New random generator, optimal genotype
evolve environment config generator
  = second head
  $ repeatCall (generations config) (evolveGeneration environment config)
  $ initialGeneration environment config generator
