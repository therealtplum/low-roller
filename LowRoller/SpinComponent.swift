//
//  SpinComponent.swift
//  LowRoller
//
//  Created by Thomas Plummer on 10/22/25.
//

import RealityKit

/// A component that spins the entity around a given axis.
struct SpinComponent: Component {
    let spinAxis: SIMD3<Float> = [0, 1, 0]
}
