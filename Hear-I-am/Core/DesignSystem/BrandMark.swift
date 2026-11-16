import SwiftUI

/// The provisional Hear I am mark: eight directional rays around an open center.
struct BrandMark: View {
    var body: some View {
        Canvas { context, size in
            let radius=min(size.width,size.height)
            let center=CGPoint(x:size.width/2,y:size.height/2)
            func point(_ angle:Double,_ r:Double) -> CGPoint {
                CGPoint(x:center.x+cos(angle)*radius*r,y:center.y+sin(angle)*radius*r)
            }
            for i in 0..<8 {
                let angle=Double(i)*Double.pi/4
                var ray=Path()
                ray.move(to:point(angle,0.17))
                if i%2 == 0 {ray.addLine(to:point(angle,0.39))}
                else {
                    ray.addLine(to:point(angle,0.22)); ray.move(to:point(angle,0.27)); ray.addLine(to:point(angle,0.39))
                }
                context.stroke(ray,with:.color(.white),lineWidth:max(1,radius*0.027))
            }
        }.background(.black,in:RoundedRectangle(cornerRadius:12)).accessibilityHidden(true)
    }
}
