import UIKit
import RxSwift
import RxCocoa
import ChameleonFramework
import SocketIO
struct Point : Codable {
    var x : Double
    var y : Double
}

enum MyErrors : Error {
    case mapping
}
class SocketViewModel {
    var incomingPoint = Variable<CGPoint?>(.zero)
    var outComingPoint = Variable<CGPoint?>(.zero)
    var disposeBag = DisposeBag()
    let jsonDecoder = JSONDecoder()
    let jsonEncoder = JSONEncoder()
    let manager = SocketManager(socketURL: URL(string: "http://192.168.100.99:3000")!, config: [.log(true), .compress])
    
    let socket :SocketIOClient!
    
    init() {
        
        socket = manager.defaultSocket
        
        socket.on(clientEvent: .connect) {data, ack in
            print("socket connected")
        }
        
        socket.on("move") {data, ack in
            //guard let cur = data[0] as? String else { return }
            print(data[0])
            if let  str = (data[0] as? String)?.data(using: .utf8) {
                if let p = try?
                    self.jsonDecoder.decode(Point.self, from:str   ) {
                    //if let p = dic["move"] {
                    self.incomingPoint.value = CGPoint(x: p.x, y: p.y)
                    // }
                }
                print (str)
                ack.with("Got your currentAmount", "dude")
            }
            
        }
        socket.connect()
        
        outComingPoint.asObservable().map({ cgp -> Point in
            if let cgp = cgp {
                return Point(x:  Double(cgp.x), y: Double(cgp.y))
            }
            return Point(x: 0, y: 0)
        }).map({ (a) -> String in
            if let data = try? self.jsonEncoder.encode(a) {
                return String(data: data, encoding: String.Encoding.utf8)!
            }
            throw MyErrors.mapping
        })
            .throttle(0.1, scheduler: MainScheduler.instance)
            .subscribe(onNext: { (s) in
                self.socket.emit("move", with: [s])
            },
                       onError: { e in  print (e) })
            .disposed(by: disposeBag)
        
    }
}


class CircleViewModel {
    
    var centerVariable = Variable<CGPoint?>(.zero) // Create one variable that will be changed and observed
    var backgroundColorObservable: Observable<UIColor>! // Create observable that will change backgroundColor based on center
    
    init() {
        setup()
    }
    
    func  setup() {
        backgroundColorObservable = centerVariable.asObservable().map({ (center) in
            guard let center = center  else { return UIColor.black }
            let red: CGFloat = ((center.x * center.y).truncatingRemainder(dividingBy:  255.0)) / 255.0 // We just manipulate red, but you can do w/e
            let green: CGFloat = center.x.truncatingRemainder(dividingBy: 255.0)/255.0
            let blue: CGFloat = center.y.truncatingRemainder(dividingBy: 255.0)/255.0
            
            return UIColor.flatten(UIColor(red: red, green: green, blue: blue, alpha: 1.0))()
            
        })
    }
    
}
class ViewController: UIViewController {
    
    var circleView: UIView!
    var circleViewModel =  CircleViewModel()
    var socketViewModel = SocketViewModel()
    var disposeBag = DisposeBag()
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    func setup() {
        // Add circle view
        circleView = UIView(frame: CGRect(origin: view.center, size: CGSize(width: 100.0, height: 100.0)))
        circleView.layer.cornerRadius = circleView.frame.width / 2.0
        circleView.center = view.center
        circleView.backgroundColor = .green
        view.addSubview(circleView)
        
        
        let gestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(circleMoved(_:)))
        circleView.addGestureRecognizer(gestureRecognizer)
        
        //circleView.rx.observe(CGPoint.self, "center")
        
        circleViewModel.backgroundColorObservable
            .subscribe(onNext: { [weak self] backgroundColor in
                UIView.animate(withDuration: 0.1) {
                    self?.circleView.backgroundColor = backgroundColor
                    // Try to get complementary color for given background color
                    let viewBackgroundColor = UIColor(complementaryFlatColorOf: backgroundColor)
                    // If it is different that the color
                    if viewBackgroundColor != backgroundColor {
                        // Assign it as a background color of the view
                        // We only want different color to be able to see that circle in a view
                        self?.view.backgroundColor = viewBackgroundColor
                    }
                }
            }).disposed(by: disposeBag)
        
        circleViewModel.centerVariable.asObservable()
            .subscribeOn(MainScheduler.instance)
            .subscribe(onNext: { (cgp) in
                UIView.animate(withDuration: 0.1) {
                    
                    self.circleView.center = cgp ?? .zero
                }
            })
            .disposed(by: disposeBag)
        
        socketViewModel.incomingPoint.asObservable()
            .bind(to: circleViewModel.centerVariable)
            .disposed(by: disposeBag)
        
        
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.socketViewModel.incomingPoint.value = CGPoint(x: 50, y: 200)
        }
    }
    
    @objc func circleMoved(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: view)
        // self.circleViewModel.centerVariable.value = location
        self.socketViewModel.outComingPoint.value = location
    }
}
