#!/bin/bash
# =============================================================================
# gitignore.io.sh - simple gitignore.io shell wrapper
# https://gist.github.com/martinec/ba3012e1a5abf954f977
# =============================================================================
# Copyright (C) 2014
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
# 
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
# 
# You should have received a copy of the GNU Lesser General Public
# License along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA.
#
# (martinec)
#
# =============================================================================

# =============================================================================
# script tools
# =============================================================================
WRAPPER_TOOL_CURL="curl"
WRAPPER_TOOL_API="https://www.gitignore.io/api"

# =============================================================================
# exit with critical error
# =============================================================================
function die_with_critical_error(){
  # send message to stderr
    echo "$@" >&2

  # exit
    exit 1;
}

# =============================================================================
# gitignore.io function caller
# =============================================================================
function gitignore () {
  # gitignore.io.sh api params
    api_params="$@"

  # curl command arguments
    curl_args="-s $WRAPPER_TOOL_API/$api_params"
  
  # build command line
    command_line=( $WRAPPER_TOOL_CURL $curl_args )

  echo "# gitignore.io.sh - a simple gitignore.io shell wrapper"
    echo "# https://gist.github.com/martinec/ba3012e1a5abf954f977"
  echo "# ./$script_name $api_params"
    echo ""

  {  
      # execute command
      eval "${command_line[@]}"
      
      # save return code
      exit_status=$?
    }

  if [ $exit_status -ne 0 ]; then
      die_with_critical_error "Aborting" "$WRAPPER_TOOL_CURL failed! " \
                                              "exit($exit_status)."
    fi
  
  # return the status
    return $exit_status
}

# =============================================================================
# test $WRAPPER_TOOL_CURL param
# =============================================================================
# test if curl param isn't empty
if [ ! "$WRAPPER_TOOL_CURL" ]; then
      die_with_critical_error "Aborting" "Trying to execute empty command"
  fi


  # =============================================================================
  # test if curl exists
  # =============================================================================
  command -v $WRAPPER_TOOL_CURL > /dev/null || \
      {
        die_with_critical_error "Aborting" "$WRAPPER_TOOL_CURL is required "\
                                             "but it's not installed"
    }

    # =============================================================================
    # main
    # =============================================================================
    script_name=$(basename "$0")

    if [ "$#" -ne 1 ]; then
          {
              echo "Usage: $script_name [list|template,...]"
              echo "   e.g $script_name list"
              echo "       $script_name c++,linux"
            } >&2
              exit 1
          fi

          message=$@;

          gitignore "$message"

