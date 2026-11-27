module PlacesHelper
  # ISO 3166 country codes by continent, for the places picker.
  CONTINENTS = {
    "Africa" => %w[ DZ AO BJ BW BF BI CV CM CF TD KM CG CD CI DJ EG GQ ER SZ ET GA GM GH GN GW KE LS LR LY MG MW ML MR MU YT MA MZ NA NE NG RE RW SH ST SN SC SL SO ZA SS SD TZ TG TN UG EH ZM ZW ],
    "Asia" => %w[ AF AM AZ BH BD BT BN KH CN CY GE HK IN ID IR IQ IL JP JO KZ KW KG LA LB MO MY MV MN MM NP KP OM PK PS PH QA SA SG KR LK SY TW TJ TH TL TR TM AE UZ VN YE ],
    "Europe" => %w[ AX AL AD AT BY BE BA BG HR CZ DK EE FO FI FR DE GI GR GG HU IS IE IM IT JE XK LV LI LT LU MT MD MC ME NL MK NO PL PT RO RU SM RS SK SI ES SJ SE CH UA GB VA ],
    "North America" => %w[ AI AG AW BS BB BZ BM BQ VG CA KY CR CU CW DM DO SV GL GD GP GT HT HN JM MQ MX MS NI PA PR BL KN LC MF PM VC SX TT TC US VI ],
    "South America" => %w[ AR BO BR CL CO EC FK GF GY PY PE SR UY VE ],
    "Oceania" => %w[ AS AU CK FJ PF GU KI MH FM NR NC NZ NU NF MP PW PG PN WS SB TK TO TV VU WF ]
  }.flat_map { |continent, codes| codes.map { [ it, continent ] } }.to_h.freeze

  def continent_for(country_code) = CONTINENTS.fetch(country_code.to_s.upcase, "Other")

  # A stable id for the URL hash, like "north-america" or "de".
  def picker_key(name) = name.to_s.parameterize
end
