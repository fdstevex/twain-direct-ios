//
//  AuthWebViewController.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2018-09-02.
//  Copyright © 2018 Visioneer, Inc. All rights reserved.
//

import UIKit
import WebKit

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
                
                stack.removeLast()
                stack.removeLast()
                stack.append(vc)
                navigationController?.setViewControllers(stack, animated: true)
            }
        }
    }
}
