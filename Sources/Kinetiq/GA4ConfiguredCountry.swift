// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A configured regional preference, not physical location or citizenship.
/// Only assigned ISO 3166-1 alpha-2 codes can reach GA4's geographic country_id.
struct GA4ConfiguredCountry: Sendable, Equatable {
    let code: String

    // Foundation's isoRegions also contains macroregions and reserved/user codes.
    // Assigned country/territory codes only; ISO 3166-1, reviewed 2026-11-09.
    // https://www.iso.org/iso-3166-country-codes.html (codes are free to use).
    static let assignedCodes: Set<String> = Set("""
        AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ
        BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ
        CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ
        DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR
        GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY
        HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP
        KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY
        MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ
        NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY
        QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ
        TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ
        VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    init?(region: Locale.Region?) {
        guard let code = region?.identifier, Self.assignedCodes.contains(code) else { return nil }
        self.code = code
    }

    /// Called only by the provider after its enabled/analytics-consent gate.
    static func current() -> Self? { Self(region: Locale.current.region) }
}