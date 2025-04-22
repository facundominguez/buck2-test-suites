module LibB where

import LibA (libA)

libB :: String
libB = "LibB imports libA: " ++ libA
