//
//  TwitterSearchViewController.swift
//  TwitterImagePipeline
//
//  Created on 3/3/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

import TwitterImagePipeline

class TweetWithMediaTableViewCell: UITableViewCell, TIPImageViewFetchHelperDataSource, TIPImageViewFetchHelperDelegate {

    private var internalTweet: TweetInfo?
    var tweet: TweetInfo? {
        get {
            return self.internalTweet
        }
        set(newTweet) {
            self.internalTweet = newTweet
            self.tweetFetchHelper?.clearImage()
            self.tweetFetchHelper?.reload()
        }
    }

    private var tweetImageView: UIImageView?
    private var tweetFetchHelper: TIPImageViewFetchHelper?

    class func reuseIdentifier() -> String
    {
        return "TweetWithMedia"
    }

    init()
    {
        super.init(style: .subtitle, reuseIdentifier: TweetWithMediaTableViewCell.reuseIdentifier())

        // logic is decoupled from the View via a "Helper" object

        // Create our helper
        self.tweetFetchHelper = TIPImageViewFetchHelper.init(delegate: self, dataSource: self)

        // Create our image view
        self.tweetImageView = UIImageView.init()
        self.tweetImageView!.tip_fetchHelper = self.tweetFetchHelper!
        self.tweetImageView!.contentMode = .scaleAspectFill
        self.tweetImageView!.clipsToBounds = true
        self.tweetImageView!.backgroundColor = UIColor.lightGray
        self.tweetImageView!.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Add image view to content
        self.contentView.addSubview(self.tweetImageView!)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder)
    {
        fatalError("\(#function) has not been implemented")
    }

    override func prepareForReuse()
    {
        super.prepareForReuse()
        self.tweet = nil
    }

    override func layoutSubviews()
    {
        super.layoutSubviews()

        var detailRect = self.detailTextLabel!.frame
        var textRect = self.textLabel!.frame
        let yDelta = detailRect.origin.y - textRect.origin.y
        textRect.origin.y = 3
        detailRect.origin.y = textRect.origin.y + yDelta
        self.detailTextLabel!.frame = detailRect
        self.textLabel!.frame = textRect

        var imageRect = self.tweetImageView!.frame
        imageRect.origin.y = detailRect.origin.y + detailRect.size.height + 3
        imageRect.origin.x = detailRect.origin.x
        imageRect.size.width = self.contentView.bounds.size.width - (2 * imageRect.origin.x)
        imageRect.size.height = self.contentView.bounds.size.height - (imageRect.origin.y + 3)
        self.tweetImageView!.frame = imageRect
    }

    // MARK: data source

    func tip_imagePipeline(for helper: TIPImageViewFetchHelper) -> TIPImagePipeline?
    {
        return APP_DELEGATE().imagePipeline
    }

    func tip_imageFetchRequest(for helper: TIPImageViewFetchHelper) -> TIPImageFetchRequest?
    {
        guard let tweetImage = self.tweet?.images.first else {
            return nil
        }

        let request = TweetImageFetchRequest.init(tweetImage: tweetImage, targetView: helper.fetchView)
        request.forcePlaceholder = APP_DELEGATE().usePlaceholder
        return request
    }

    // MARK: delegate

    func tip_fetchHelper(_ helper: TIPImageViewFetchHelper, shouldUpdateImageWithPreviewImageResult previewImageResult: TIPImageFetchResult) -> Bool
    {
        return true
    }

    func tip_fetchHelper(_ helper: TIPImageViewFetchHelper, shouldContinueLoadingAfterFetchingPreviewImageResult previewImageResult: TIPImageFetchResult) -> Bool
    {
        if previewImageResult.imageIsTreatedAsPlaceholder {
            return true
        }

        if let request = helper.fetchRequest, let options = request.options {
            if options.contains(.treatAsPlaceholder) {
                // would be a downgrade, stop
                return false
            }
        }

        guard let fetchImageView = helper.fetchView else {
            // don't have a view to compare with, stop
            return false
        }

        let originalDimensions = previewImageResult.imageOriginalDimensions
        let viewDimensions = TIPDimensionsFromView(fetchImageView)
        if (originalDimensions.height >= viewDimensions.height && originalDimensions.width >= viewDimensions.width) {
            return false
        }

        return true
    }

    func tip_fetchHelper(_ helper: TIPImageViewFetchHelper, shouldLoadProgressivelyWithIdentifier identifier: String, url URL: URL, imageType: String, originalDimensions: CGSize) -> Bool
    {
        return true
    }

//    @objc func tip_fetchHelper(_ helper: TIPImageViewFetchHelper, shouldReloadAfterDifferentFetchCompletedWith image: UIImage, dimensions: CGSize, identifier: String, url URL: URL, treatedAsPlaceholder placeholder: Bool, manuallyStored: Bool) -> Bool
//    {
//
//    }

}

class TwitterSearchViewController: UIViewController, UISearchResultsUpdating, UISearchControllerDelegate, UISearchBarDelegate, UITableViewDelegate, UITableViewDataSource {

    private var searchController: UISearchController?
    private var tableView: UITableView?
    private var term: String?
    private var tweets: [TweetInfo]?

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?)
    {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.navigationItem.title = "Twitter Search"
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder)
    {
        fatalError("\(#function) has not been implemented")
    }

    override func viewDidLoad()
    {
        super.viewDidLoad()

        self.searchController = UISearchController.init(searchResultsController: nil)
        self.searchController!.searchResultsUpdater = self
        self.searchController!.definesPresentationContext = true
        self.searchController!.searchBar.delegate = self
        self.searchController!.searchBar.sizeToFit()

        self.tableView = UITableView.init(frame: self.view.bounds, style: .plain)
        self.tableView!.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.tableView!.delegate = self
        self.tableView!.dataSource = self

        self.tableView!.tableHeaderView = self.searchController!.searchBar
        self.view.addSubview(self.tableView!)
    }

    // MARK: table view

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        if let count = self.tweets?.count {
            return count
        }
        return 0
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        tableView.deselectRow(at: indexPath, animated: true)
        if let imageInfo: TweetImageInfo = self.tweets?[indexPath.row].images.first {
            let vc = ZoomingTweetImageViewController.init(tweetImage: imageInfo)
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        let hasImages: Bool
        let tweet = self.tweets?[indexPath.row]
        if let tweet = tweet {
            hasImages = tweet.images.count > 0
        } else {
            hasImages = false
        }

        var cell: UITableViewCell? = tableView.dequeueReusableCell(withIdentifier: (hasImages) ? TweetWithMediaTableViewCell.reuseIdentifier() : "TweetNoMedia")
        if nil == cell {
            if hasImages {
                cell = TweetWithMediaTableViewCell.init()
            } else {
                cell = UITableViewCell.init(style: .subtitle, reuseIdentifier: "TweetNoMedia")
            }
        }

        cell!.textLabel?.text = tweet?.handle
        cell!.detailTextLabel?.text = tweet?.text
        if hasImages {
            (cell as! TweetWithMediaTableViewCell).tweet = tweet
        }

        return cell!
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat
    {
        if let tweet = self.tweets?[indexPath.row] {
            if tweet.images.count > 0 {
                return 180
            }
        }

        return 44
    }

//    @objc func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat
//    {
//        if let tweet = self.tweets?[indexPath.row] {
//            if tweet.images.count > 0 {
//                return 180
//            }
//        }
//
//        return 44
//    }

    // MARK: Search Controller

    func updateSearchResults(for searchController: UISearchController)
    {
    }

#if targetEnvironment(macCatalyst)
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String)
    {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        self.perform(#selector(_triggerSearch),
                     with: nil,
                     afterDelay: 0.5)
    }
#endif

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar)
    {
        self._triggerSearch()
    }

    @objc
    func _triggerSearch()
    {
        guard let searchBar = self.searchController?.searchBar else {
            return
        }

        let search = searchBar.text
        self.term = search
        self.searchController!.isActive = false
        self.searchController!.searchBar.isUserInteractionEnabled = false
        searchBar.text = self.term

        TwitterAPI.sharedInstance().search(forTerm: (nil != self.term) ? self.term! : "",  count: APP_DELEGATE().searchCount) { tweets, _ in

            self.tweets = tweets
            self.searchController?.searchBar.isUserInteractionEnabled = true
            self.tableView?.reloadData()
        }
    }

    func willPresentSearchController(_ searchController: UISearchController)
    {
        self.searchController!.searchBar.text = self.term
    }
}
