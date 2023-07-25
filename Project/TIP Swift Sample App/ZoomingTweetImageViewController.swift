//
//  ZoomingTweetImageViewController.swift
//  TwitterImagePipeline
//
//  Created on 3/2/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

import TwitterImagePipeline

class ZoomingTweetImageViewController: UIViewController, UIScrollViewDelegate, TIPImageFetchDelegate {

    var tweetImageInfo: TweetImageInfo?

    private var scrollView: UIScrollView?
    private var imageView: UIImageView?
    private var progressView: UIProgressView?

    private var doubleTapGestureRecognizer: UITapGestureRecognizer?

    private var fetchOp: TIPImageFetchOperation?

    init(tweetImage imageInfo:TweetImageInfo)
    {
        self.init()
        self.tweetImageInfo = imageInfo
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?)
    {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.navigationItem.title = "Tweet Image"
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder)
    {
        fatalError("\(#function) has not been implemented")
    }

    override func viewDidLoad()
    {
        super.viewDidLoad()
        var targetSize = self.tweetImageInfo!.originalDimensions
        let scale = UIScreen.main.scale
        targetSize.height /= scale
        targetSize.width /= scale

        self.progressView = UIProgressView.init(frame: CGRect(x: 0, y: 0, width: self.view.bounds.size.width, height: 4.0))
        self.progressView!.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        self.progressView!.tintColor = UIColor.yellow
        self.progressView!.progress = 0

        self.imageView = UIImageView.init(frame: CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height))
        self.imageView!.contentMode = .scaleAspectFill
        self.imageView!.clipsToBounds = true
        self.imageView!.backgroundColor = UIColor.gray

        self.scrollView = UIScrollView.init(frame: self.view.bounds)
        self.scrollView!.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.scrollView!.backgroundColor = UIColor.black

        let tapSelector: Selector = #selector(self.doubleTapTriggered(_:))
        self.doubleTapGestureRecognizer = UITapGestureRecognizer.init(target: self, action: tapSelector)
        self.doubleTapGestureRecognizer!.numberOfTapsRequired = 2

        self.imageView!.image = nil
        self.imageView!.addGestureRecognizer(self.doubleTapGestureRecognizer!)
        self.imageView!.isUserInteractionEnabled = true

        self.scrollView!.delegate = self
        self.scrollView!.minimumZoomScale = 0.01 // start VERY small
        self.scrollView!.maximumZoomScale = 2.0
        self.scrollView!.contentSize = targetSize

        self.view!.addSubview(self.scrollView!)
        self.view!.addSubview(self.progressView!)
        self.scrollView!.addSubview(self.imageView!)
        self.scrollView!.zoom(to: self.imageView!.frame, animated: false)
        self.scrollView!.minimumZoomScale = self.scrollView!.zoomScale // readjust minimum
        if (self.scrollView!.minimumZoomScale > self.scrollView!.maximumZoomScale) {
            self.scrollView!.maximumZoomScale = self.scrollView!.minimumZoomScale
        }

        self.scrollViewDidZoom(self.scrollView!)
        self.load()
    }

    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        self.scrollViewDidZoom(self.scrollView!)
        var frame = self.progressView!.frame
        frame.origin.y = self.scrollView!.contentInset.top
        self.progressView!.frame = frame
    }

    // MARK: Double tap

    @objc private func doubleTapTriggered(_ tapper: UITapGestureRecognizer)
    {
        if tapper.state == .recognized, let scrollView = self.scrollView {
            if scrollView.zoomScale == scrollView.maximumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                scrollView.setZoomScale(scrollView.maximumZoomScale, animated: true)
            }
        }
    }

    // MARK: Scroll view delegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView?
    {
        return self.imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView)
    {
        let offsetX = max((scrollView.bounds.size.width - scrollView.contentInset.left - scrollView.contentInset.right - scrollView.contentSize.width) * 0.5, 0.0)
        let offsetY = max((scrollView.bounds.size.height - scrollView.contentInset.top - scrollView.contentInset.bottom - scrollView.contentSize.height) * 0.5, 0.0)

        self.imageView?.center = CGPoint(x: scrollView.contentSize.width * 0.5 + offsetX, y: scrollView.contentSize.height * 0.5 + offsetY)
    }

    // MARK: private

    private func load()
    {
        let request = TweetImageFetchRequest.init(tweetImage: self.tweetImageInfo!, targetView: self.imageView!)
        self.fetchOp = APP_DELEGATE().imagePipeline!.operation(with: request, context: nil, delegate: self)
        APP_DELEGATE().imagePipeline!.fetchImage(with: self.fetchOp!)
    }

    // MARK: TIP delegate

    func tip_imageFetchOperationDidStart(_ op: TIPImageFetchOperation)
    {
        print("starting Zoom fetch...")
    }

    func tip_imageFetchOperation(_ op: TIPImageFetchOperation, willAttemptToLoadFrom source: TIPImageLoadSource)
    {
        print("...attempting load from next source: \(source)...")
    }

    func tip_imageFetchOperation(_ op: TIPImageFetchOperation, didLoadPreviewImage previewResult: TIPImageFetchResult, completion: @escaping TIPImageFetchDidLoadPreviewCallback)
    {
        print("...preview loaded...")
        self.progressView!.tintColor = UIColor.blue
        self.imageView!.image = previewResult.imageContainer.image
        completion(.continueLoading)
    }

    func tip_imageFetchOperation(_ op: TIPImageFetchOperation, shouldLoadProgressivelyWithIdentifier identifier: String, url URL: URL, imageType: String, originalDimensions: CGSize) -> Bool
    {
        if nil != self.imageView?.image {
            return false
        }
        return true
    }

    func tip_imageFetchOperation(_ op: TIPImageFetchOperation, didUpdateProgressiveImage progressiveResult: TIPImageFetchResult, progress: Float)
    {
        print("...progressive update (\(progress))...")
        self.progressView!.tintColor = UIColor.orange
        self.progressView!.setProgress(progress, animated: true)
        self.imageView!.image = progressiveResult.imageContainer.image
    }

    func tip_imageFetchOperation(_ op: TIPImageFetchOperation, didLoadFirstAnimatedImageFrame progressiveResult: TIPImageFetchResult, progress: Float)
    {
        print("...animated first frame (\(progress))...")
        self.progressView!.tintColor = UIColor.purple
        self.progressView!.setProgress(progress, animated: true)
        self.imageView!.image = progressiveResult.imageContainer.image
    }

    func tip_imageFetchOperation(_ op: TIPImageFetchOperation, didUpdateProgress progress: Float)
    {
        print("...progress (\(progress))...")
        self.progressView!.setProgress(progress, animated: true)
    }

    func tip_imageFetchOperation(_ op: TIPImageFetchOperation, didLoadFinalImage finalResult: TIPImageFetchResult)
    {
        print("...completed zoom fetch")
        self.progressView!.tintColor = UIColor.green
        self.progressView!.setProgress(1.0, animated: true)
        self.imageView!.image = finalResult.imageContainer.image
        self.fetchOp = nil
    }

    func tip_imageFetchOperation(_ op: TIPImageFetchOperation, didFailToLoadFinalImage error: Error)
    {
        print("...failed zoom fetch: \(error)")
        self.progressView!.tintColor = UIColor.red
        self.fetchOp = nil
    }
}
