#!/bin/bash
# Fetch the 30 most recent sponsors of tw93 via gh api graphql.
# Uses the minimal query that works on a token without `read:user` scope.
# Adding createdAt or privacyLevel requires `read:user`.

set -euo pipefail

if ! command -v gh > /dev/null 2>&1; then
    echo "gh CLI is required" >&2
    exit 1
fi

gh api graphql -f query='{
  user(login:"tw93"){
    sponsorshipsAsMaintainer(first:30, orderBy:{field:CREATED_AT, direction:DESC}){
      nodes{
        sponsorEntity{
          ... on User{login}
          ... on Organization{login}
        }
      }
    }
  }
}' --jq '.data.user.sponsorshipsAsMaintainer.nodes[].sponsorEntity.login'
