//
//  CloudDiscoverTableViewController.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2018-09-18.
//  Copyright © 2018 Visioneer, Inc. All rights reserved.
//

import UIKit

// Table view that lets the user pick from a nearby TWAIN Cloud,
// as discovered through Bonjour
class CloudDiscoverTableViewController: UITableViewController {

    var clouds = [CloudInfo]()
    lazy var serviceDiscoverer = ServiceDiscoverer(delegate: self)
    let scannersChecked = Set<URL>()
    let sessions = [Session]()
    
    var cloudSelectedHandler: ((URL)->())?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Start discovering
        serviceDiscoverer.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        serviceDiscoverer.stop()
        super.viewWillDisappear(false)
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return clouds.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
        cell?.textLabel?.text = clouds[indexPath.row].url.absoluteString
        return cell ?? UITableViewCell()
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        cloudSelectedHandler?(clouds[indexPath.row].url)
        self.navigationController?.popViewController(animated: true)
    }
}

extension CloudDiscoverTableViewController : ServiceDiscovererDelegate {
    func discoverer(_ discoverer: ServiceDiscoverer, didDiscover scanners: [ScannerInfo]) {
        scanners.forEach { (scannerInfo) in
            guard !scannersChecked.contains(scannerInfo.url) else {
                // Already queried this scanner
                return
            }

            log.info("Discovered \(scannerInfo), requesting infoex")

            let session = Session(url: scannerInfo.url)
            session.getScannerInfo(completion: { (response) in
                OperationQueue.main.addOperation {
                    switch response {
                    case .Failure:
                        // Ignore
                        break;
                    case .Success(let infoex):
                        infoex.clouds?.forEach({ (newCloudInfo) in
                            if !self.clouds.contains(where: { (cloudInfo) -> Bool in
                                return cloudInfo.url == newCloudInfo.url
                            }) {
                                self.clouds.append(newCloudInfo)
                                self.tableView.reloadData()
                            }
                        })
                    }
                }
            })
        }
    }
}
