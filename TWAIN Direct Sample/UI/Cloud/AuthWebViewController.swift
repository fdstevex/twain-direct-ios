//
//  AuthWebViewController.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2018-09-02.
//  Copyright © 2018 Visioneer, Inc. All rights reserved.
//

import UIKit
import WebKit

/**
 UIViewController that wraps a WKWebView, which the user uses to authenticate
 with their OAuth2 cloud service. This process redirects back to the TWAIN Cloud service
 with the accessToken and refreshToken as URL parameters.
 
 We intercept this in a WKNavigationDelegate, below, store the tokens and then
 pop back up the navigation stack.
*/

class AuthWebViewController: UIViewController {

    var apiURL: URL!
    var authURL: URL!
    
    @IBOutlet weak var webView: WKWebView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        webView.navigationDelegate = self
        
        let request = URLRequest(url: authURL)
        webView.load(request)
    }
}

extension AuthWebViewController : WKNavigationDelegate {
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        // Received a redirect - watch for authorization_token and refresh_token parameters
        
        guard let url = webView.url else {
            return
        }
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        
        guard let accessToken = components?.queryItems?.first(where: { $0.name == "authorization_token" })?.value,
            let refreshToken = components?.queryItems?.first(where: { $0.name == "refresh_token" })?.value else {
                // Not the response we're waiting for
                return
        }

        // Proceed to scanner picker
        guard var stack = navigationController?.viewControllers else {
            log.error("No navigation controller vc stack?")
            return
        }
        
        if let vc = storyboard?.instantiateViewController(withIdentifier: "scannerPicker") as? ScannerPickerTableViewController {
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                appDelegate.cloudConnection = CloudConnection(apiURL: apiURL, accessToken: accessToken, refreshToken: refreshToken)
                appDelegate.cloudConnection?.makeSelected()
                vc.cloudConnection = appDelegate.cloudConnection
                
                // At this point, the user has on the navigation stack:
                //   MainTableViewController
                //   AuthWebViewController
                //   This VC
                // What we want is
                //   MainTableViewController
                //   ScannerPickerTableViewController
                // So we'll update the navigation controller's view stack directly,
                // removing two, adding one, and then let setViewControllers figure
                // out how to animate it.
                
                stack.removeLast()
                stack.removeLast()
                stack.append(vc)
                navigationController?.setViewControllers(stack, animated: true)
            }
        }
    }
}
