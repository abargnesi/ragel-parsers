#!/usr/bin/env bash

find lib -name "*.rl" -exec ragel -I lib/bel_parser/parsers/common/ -I lib/bel_parser/parsers/expression/ -I lib/bel_parser/parsers/bel_script/ -R -F1 -L {} \;
