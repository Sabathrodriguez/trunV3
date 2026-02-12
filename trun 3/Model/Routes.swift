//
//  Routes.swift
//  trun
//
//  Created by Sabath  Rodriguez on 2/6/25.
//

enum Routes: String, CaseIterable, Identifiable {
    case three_red, six_red, ten_red, three_gold, six_gold, ten_gold, three_green,
         six_green, ten_green
    
    var id: Self { self }
}
