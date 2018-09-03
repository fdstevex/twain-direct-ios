//
//  CloudAuthViewController.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2018-09-02.
//  Copyright © 2018 Visioneer, Inc. All rights reserved.
//

import UIKit

class CloudAuthViewController: UIViewController {

    @IBOutlet weak var apiField: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    func authenticate(_ service: String) {
        guard let urlString = apiField.text else {
            log.error("nil URL")
            return
        }
        
        guard let apiURL = URL(string:urlString) else {
            log.error("Unable to parse URL \(urlString)")
            return
        }

        let authURL = apiURL.appendingPathComponent("authentication/signin/" + service)
        guard let vc = storyboard?.instantiateViewController(withIdentifier: "authWebView") as? AuthWebViewController else {
            log.error("Missing authWebView from storyboard")
            return
        }
        
        vc.authURL = authURL
        vc.apiURL = apiURL
        
        navigationController?.pushViewController(vc, animated: true)
    }
    
    @IBAction func didTapAuthenticateWithFacebook(_ sender: Any) {
        authenticate("facebook")
    }
    
    @IBAction func didTapAuthenticateWithGoogle(_ sender: Any) {
        authenticate("google")
    }
}
