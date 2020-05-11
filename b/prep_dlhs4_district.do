/* clean dlhs4 district-level data on hospital capacity */

/**********************/
/* district hospitals */
/**********************/

use $health/DLHS4_FacilitySurveyData/AHS_FACILITY/AHS_dh, clear
append using $health/DLHS4_FacilitySurveyData/NON_AHS_FACILITY/DH_NONAHS

/* merge in pc11 districts */
merge m:1 state dist using $health/DLHS4_FacilitySurveyData/dlhs4_district_key, keepusing(pc11_state_id pc11_state_name pc11_district_id pc11_district_name)
drop if _merge == 2
drop _merge

/* generate bed count */
gen dh_beds = qd2

/* generate facility count var */
gen dh_count = 1

/* generate staff count var */
egen dh_staff = rowtotal(qd2*_r)

/* generate icu beds count var */
gen dh_icu_beds = qd68_total

/* collapse */
collapse (sum) dh_beds dh_count dh_staff dh_icu_beds qd213_r qd214_c, by(pc11_state_id pc11_district_id)

/* clean up */
label var dh_beds "Total beds in district hospitals"
label var dh_count "Total district hospitals"
label var dh_staff "Total staff district hospitals"
label var dh_icu_beds "Total beds in intensive medicare units"
ren qd213_r dh_doc_reg
label var dh_doc_reg "General Duty Doctor (regular)"
ren qd214_c dh_doc_contract
label var dh_doc_contract "General Duty Doctor (contractual)"

/* save */
save $tmp/dlhs4_dh_dist_beds, replace

/****************************/
/* community health centers */
/****************************/
use $health/DLHS4_FacilitySurveyData/AHS_FACILITY/AHS_chc.dta , clear
append using $health/DLHS4_FacilitySurveyData/NON_AHS_FACILITY/CHC_NONAHS.dta

/* merge in pc11 districts */
merge m:1 state dist using $health/DLHS4_FacilitySurveyData/dlhs4_district_key.dta, keepusing(pc11_state_id pc11_state_name pc11_district_id pc11_district_name)
drop if _merge == 2
drop _merge

/* gen bed count */
gen chc_beds = qc571

/* generate facility count var */
gen chc_count = 1

/* generate staff count var */
egen chc_staff = rowtotal(qc2*a)

/* gen bed count with available ventilator, mask, and oxygen */
gen chc_beds_ven = qc571 if qc72 < 3 & (qc73 < 3 | qc44 < 3) & qc78 < 3 & qc554k < 3

/* collapse */
collapse (sum) chc_beds chc_count chc_staff chc_beds_ven qc22a qc22b, by(pc11_state_id pc11_district_id)

/* clean up */
label var chc_beds "Total beds in community health centers"
label var chc_count "Total community health centers"
label var chc_staff "Total staff in community health centers"
label var chc_beds_ven "Total beds in CHC with ventilator, oxygen, and cardiac monitor"
ren qc22a chc_doc_reg
label var chc_doc_reg "number of regular physician in position at CHC"
ren qc22b chc_doc_contract
label var chc_doc_contract "number of contractual physician in position at CHC"

/* save */
save $tmp/dlhs4_chc_dist_beds, replace

/****************************/
/* primary health centers */
/****************************/

use $health/DLHS4_FacilitySurveyData/AHS_FACILITY/AHS_phc.dta , clear
append using $health/DLHS4_FacilitySurveyData/NON_AHS_FACILITY/PHC_NONAHS.dta

/* merge in pc11 districts */
merge m:1 state dist using $health/DLHS4_FacilitySurveyData/dlhs4_district_key.dta, keepusing(pc11_state_id pc11_state_name pc11_district_id pc11_district_name)
drop if _merge == 2
drop _merge

/* generate bed count */
gen phc_beds = qp429b 

/* generate facility count var */
gen phc_count = 1

/* generate staff count var */
egen phc_staff = rowtotal(qp2*a)

/* generate population served for calculation of multiplier */
gen phc_pop = qp3

/* gen bed count with oxygen */
gen phc_beds_oxy = qp429b if qp428kk < 3

/* drop if bad data (zero pop/staff, or missing data) -- assuming random bad data so multiplier accurate */
drop if mi(phc_pop) | phc_pop == 0 | mi(phc_beds) | phc_staff == 0

/* collapse */
collapse (sum) phc_beds phc_count phc_staff phc_pop phc_beds_oxy qp21a qp21b, by(pc11_state_id pc11_district_id)

/* clean up */
label var phc_beds "Total beds in primary health centers"
label var phc_count "Total primary health centers"
label var phc_staff "Total staff in primary health centers"
label var phc_pop "Population covered by sampled primary health centers"
label var phc_beds_oxy "Total beds in PHC with oxygen cylinders"
ren qp21a phc_doc_reg
label var phc_doc_reg "Regular MO in position at PHC"
ren qp21b phc_doc_contract
label var phc_doc_contract "contactual MO in position at PHC"

/* save */
save $tmp/dlhs4_phc_dist_beds, replace

/******************/
/* merge together */
/******************/
use $tmp/dlhs4_dh_dist_beds, clear
merge 1:1 pc11_state_id pc11_district_id using $tmp/dlhs4_chc_dist_beds, gen(_m_chc)
drop _m_chc
merge 1:1 pc11_state_id pc11_district_id using $tmp/dlhs4_phc_dist_beds, gen(_m_phc)
drop _m_phc

/* get district population */
merge 1:1 pc11_district_id using $pc11/pc11_pca_district_clean, keepusing(pc11_pca_tot_p) gen(_m_pca)
drop if _m_pca == 2
drop _m_pca

/* replace missing with 0 */
foreach i in dh chc phc {
  foreach j in beds count staff doc_reg doc_contract {
    replace `i'_`j' = 0 if mi(`i'_`j')
  }
}

/* generate multiplier for PHC numbers */
gen phc_mult = pc11_pca_tot_p / phc_pop
replace phc_mult = 0 if mi(phc_mult)
label var phc_mult "Sampling weight on PHCs"

/* generate total beds in district */
gen total_beds = dh_beds + chc_beds + (phc_beds * phc_mult)
gen total_staff = dh_staff + chc_staff + (phc_staff * phc_mult)
gen total_facilities = dh_count + chc_count + (phc_count * phc_mult)
gen total_doc_reg = dh_doc_reg + chc_doc_reg + (phc_doc_reg * phc_mult)
gen total_doc_contract = dh_doc_contract + chc_doc_contract + (phc_doc_contract * phc_mult)
gen total_doc = total_doc_reg + total_doc_contract

/* label remaining variables */
label var total_beds "Total beds in all public facilities (DH + CHC + PHC)"
label var total_staff "Total staff in all public facilities (DH + CHC + PHC)"
label var total_facilities "Total number of public facilities (DH + CHC + PHC)"
label var pc11_state_id "2011 Population Census State ID"
label var pc11_district_id "2011 Population Census District ID"
label var total_doc_reg "Total regular general duty doctors"
label var total_doc_contract "Total contract general duty doctors"
label var total_doc "Total general duty doctors"

/* clean up */
ren * dlhs4_*
ren dlhs4_pc11* pc11*
sort pc11_state_id pc11_district_id pc11_pca_tot_p

/* save */
label var pc11_state_id "PC11 state id"
label var pc11_district_id "PC11 district id"
compress
save $health/hosp/dlhs4_hospitals_dist, replace

/* save a version in the public repo */
if mi("$covidpub") {
  di "Not in covid context; use set_context to continue"
  error 345
}
save $covidpub/hospitals/dlhs4_hospitals_dist, replace

/* save a CSV version */
cap mkdir $covidpub/hospitals/csv
export delimited $covidpub/hospitals/csv/dlhs4_hospitals_dist, replace
