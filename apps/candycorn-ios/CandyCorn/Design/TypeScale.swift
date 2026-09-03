import SwiftUI

enum TypeScale {
    static let display = Font.custom("AvenirNext-Bold", size: 43, relativeTo: .largeTitle)
    static let pageTitle = Font.custom("AvenirNext-Bold", size: 32, relativeTo: .largeTitle)
    static let question = Font.custom("AvenirNext-Bold", size: 25, relativeTo: .title2)
    static let section = Font.custom("AvenirNext-DemiBold", size: 22, relativeTo: .title3)
    static let sectionCompact = Font.custom("AvenirNext-DemiBold", size: 19, relativeTo: .headline)
    static let body = Font.custom("AvenirNext-Regular", size: 16, relativeTo: .body)
    static let bodyMedium = Font.custom("AvenirNext-Medium", size: 16, relativeTo: .body)
    static let label = Font.custom("AvenirNext-Medium", size: 14, relativeTo: .subheadline)
    static let provenance = Font.custom("AvenirNext-Regular", size: 13, relativeTo: .caption)
    static let button = Font.custom("AvenirNext-DemiBold", size: 17, relativeTo: .headline)
    static let timer = Font.custom("AvenirNext-DemiBold", size: 64, relativeTo: .largeTitle).monospacedDigit()
}
