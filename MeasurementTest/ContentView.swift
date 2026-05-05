//
//  ContentView.swift
//  MeasurementTest
//
//  Created by Oskar Hertzman on 2026-04-16.
//

import SwiftUI
import RealityKit

struct ContentView: View {
	init() {
		// Register the billboard logic before the ARView is created
		BillboardComponent.registerComponent()
	}
	
    var body: some View {
        MeasurementExperienceView()
    }
}

#Preview {
    ContentView()
}
