#! /bin/bash

if [ -f ./docset.zip ]; then
    cp ./docset.zip ~/Library/Developer/Shared/Documentation/DocSets/docset.zip
    pushd ~/Library/Developer/Shared/Documentation/DocSets
    rm -rf com.twitter.TwitterImagePipeline.docset
    unzip ./docset.zip
    popd
else
    echo "no docset.zip to install"
fi
