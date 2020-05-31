//
//  TweetImageFetchRequest.swift
//  TwitterImagePipeline
//
//  Created on 3/3/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

//let kSMALL = "small"
//let kMEDIUM = "medium"
//let kLARGE = "large"
//
//struct VariantInfo {
//    var name: String
//    var dim: CGFloat
//
//    init(_ name: String, dimensions dim: CGFloat) {
//        self.name = name
//        self.dim = dim
//    }
//}
//
//let sVariantSizeMap: [VariantInfo] = [
//    VariantInfo.init(kSMALL, dimensions: 680),
//    VariantInfo.init(kMEDIUM, dimensions: 1200),
//    VariantInfo.init(kLARGE, dimensions: 2048)
//]

import TwitterImagePipeline

class TweetImageFetchRequest: NSObject, TIPImageFetchRequest {

    var forcePlaceholder: Bool

    private let tweetImageInfo: TweetImageInfo
    private var internalImageURL: URL?

    @objc var targetDimensions: CGSize

    @objc var targetContentMode: UIView.ContentMode

    @objc var imageIdentifier: String? {
        return self.tweetImageInfo.baseURLString
    }

    @objc var imageURL: URL {
        if nil == self.internalImageURL {
            if self.forcePlaceholder {
                self.internalImageURL = URL.init(string: "placeholder://placeholder.com/placeholder.jpg")
            } else {
                let URLString: String
                if self.tweetImageInfo.baseURLString.hasPrefix("https://pbs.twimg.com/media/") {
                    let variantName = TweetImageDetermineVariant(self.tweetImageInfo.originalDimensions, self.targetDimensions, self.targetContentMode)
                    let format = APP_DELEGATE().searchWebP ? "webp" : self.tweetImageInfo.format
                    URLString = "\(self.tweetImageInfo.baseURLString)?format=\(format)&name=\(variantName)"
                } else {
                    URLString = "\(self.tweetImageInfo.baseURLString).\(self.tweetImageInfo.format)"
                }
                self.internalImageURL = URL.init(string: URLString)
            }
        }

        return self.internalImageURL!
    }
    @objc var options: TIPImageFetchOptions {
        return self.forcePlaceholder ? [.treatAsPlaceholder] : []
    }

    init(tweetImage tweet: TweetImageInfo, targetView view: UIView?)
    {
        self.forcePlaceholder = false
        self.tweetImageInfo = tweet
        self.targetContentMode = view?.contentMode ?? .center
        self.targetDimensions = TIPDimensionsFromView(view)
    }
}
