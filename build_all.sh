#!/usr/bin/env bash

find lib -name "*.rl" -exec ragel -I lib/bel/parsers/common/ -I lib/bel/parsers/expression/ -I lib/bel/parsers/bel_script/ -R -F1 -L {} \;
