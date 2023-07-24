//
//  AppDelegate.swift
//  TIP Swift Sample App
//
//  Created on 3/2/17.
//  Copyright © 2020 Twitter. All rights reserved.
//

import TwitterImagePipeline
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, TIPImagePipelineObserver, TIPLogger, TIPImageAdditionalCache, TwitterAPIDelegate {

    // MARK: UIApplicationDelegate variables

    var window: UIWindow?

    // MARK: internal variables

    var imagePipeline: TIPImagePipeline?

    // MARK: variables needed by @objc

    @objc var searchCount: UInt = 100
    @objc var searchWebP: Bool = false
    @objc var usePlaceholder: Bool = false

    @objc private var debugInfoVisible: Bool {
        get {
            return TIPImageViewFetchHelper.isDebugInfoVisible
        }
        set(visible) {
            TIPImageViewFetchHelper.isDebugInfoVisible = visible
        }
    }

    // MARK: private variables

    private var tabBarController: UITabBarController?

    private var opCount: Int = 0
    private var placeholder: UIImage?

    // MARK: UIApplicationDelegate functions

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    {
        let tipConfig = TIPGlobalConfiguration.sharedInstance()
        tipConfig.logger = self
        tipConfig.serializeCGContextAccess = true
        tipConfig.isClearMemoryCachesOnApplicationBackgroundEnabled = true
        tipConfig.add(self)

        let catalogue = TIPImageCodecCatalogue.sharedInstance()
        catalogue.setCodec(TIPXWebPCodec(preferredCodec: nil), forImageType: TIPImageTypeWEBP)

        self.imagePipeline = TIPImagePipeline(identifier: "Twitter.Example")
        self.imagePipeline?.additionalCaches = [self]

        TwitterAPI.sharedInstance().delegate = self


        let lightBlueColor = UIColor(red: 150.0/255.0, green: 215.0/255.0, blue: 1.0, alpha: 0.0)

        UISearchBar.appearance().barTintColor = lightBlueColor
        UISearchBar.appearance().tintColor = UIColor.white
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).tintColor = lightBlueColor
        UINavigationBar.appearance().barTintColor = lightBlueColor
        UINavigationBar.appearance().tintColor = UIColor.white
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: UIColor.white]
        UITabBar.appearance().barTintColor = lightBlueColor
        UITabBar.appearance().tintColor = UIColor.white
        UISlider.appearance().minimumTrackTintColor = lightBlueColor
        UISlider.appearance().tintColor = lightBlueColor
        UIWindow.appearance().tintColor = lightBlueColor

        self.window = UIWindow.init(frame: UIScreen.main.bounds)

        let navCont1 = UINavigationController.init(rootViewController: TwitterSearchViewController.init())
        navCont1.tabBarItem = UITabBarItem.init(title: "Search", image: UIImage(named: "first"), tag: 1)
        let navCont2 = UINavigationController.init(rootViewController: SettingsViewController.init())
        navCont2.tabBarItem = UITabBarItem.init(title: "Settings", image: UIImage(named: "second"), tag: 2)
        let navCont3 = UINavigationController.init(rootViewController: InspectorViewController.init())
        navCont3.tabBarItem = UITabBarItem.init(title: "Inspector", image: UIImage(named: "first"), tag: 3)

        self.tabBarController = UITabBarController.init()
        self.tabBarController?.viewControllers = [ navCont1, navCont2, navCont3 ]

        self.window?.rootViewController = self.tabBarController
        self.window?.backgroundColor = UIColor.orange
        self.window?.makeKeyAndVisible()

        return true
    }

    // MARK: private functions

    private func incrementNetworkOperations()
    {
        if (Thread.isMainThread) {
            self.incOps()
        } else {
            DispatchQueue.main.async {
                self.incOps()
            }
        }
    }

    private func decrementNetworkOperations()
    {
        if (Thread.isMainThread) {
            self.decOps()
        } else {
            DispatchQueue.main.async {
                self.decOps()
            }
        }
    }

    private func incOps()
    {
        self.opCount += 1
        if (self.opCount > 0) {
            UIApplication.shared.isNetworkActivityIndicatorVisible = true
        }
    }

    private func decOps()
    {
        self.opCount -= 1
        if (self.opCount <= 0) {
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
        }
    }

    // MARK: API Delegate

    func apiWorkStarted(_ api: TwitterAPI)
    {
        self.incrementNetworkOperations()
    }

    func apiWorkFinished(_ api: TwitterAPI)
    {
        self.decrementNetworkOperations()
    }

    // MARK: Observer

    func tip_imageFetchOperation(_ op: TIPImageFetchOperation, didStartDownloadingImageAt URL: URL)
    {
        self.incrementNetworkOperations()
    }

    func tip_imageFetchOperation(_ op: TIPImageFetchOperation, didFinishDownloadingImageAt URL: URL, imageType type: String, sizeInBytes byteSize: UInt, dimensions: CGSize, wasResumed: Bool)
    {
        self.decrementNetworkOperations()
    }

    // MARK: Logger

    func tip_log(with level: TIPLogLevel, file: String, function: String, line: Int32, message: String)
    {
        let levelString: String
        switch (level) {
        case .emergency,
             .alert,
             .critical,
             .error:
            levelString = "ERR"
        case .warning:
            levelString = "WRN"
        case .notice,
             .information:
            levelString = "INF"
        case .debug:
            levelString = "DBG"
        @unknown default:
            fatalError("unknown objc TIPLogLevel enum (\(level))")
        }
        print("[\(levelString): \(message)")
    }

    // MARK: Additional Cache

    func tip_retrieveImage(for URL: URL, completion: @escaping TIPImageAdditionalCacheFetchCompletion)
    {
        var image: UIImage?
        let lastPathComponent: String? = URL.lastPathComponent
        if let scheme = URL.scheme, let host = URL.host, let lastPathComponent = lastPathComponent {
            if scheme == "placeholder" && host == "placeholder.com" && lastPathComponent == "placeholder.jpg" {
                if self.placeholder == nil {
                    self.placeholder = UIImage(named: "placeholder.jpg")
                }
                image = self.placeholder
            }
        }
        completion(image)
    }
}

func APP_DELEGATE() -> AppDelegate
{
    return UIApplication.shared.delegate as! AppDelegate
}
