/************************************/
/* define global sets of conditions */
/************************************/

/* collapse the data to age-sex bins */
use $tmp/combined, clear

/*********************************************************/
/* COMBINE RISK FACTORS  */
/*********************************************************/
/* for each person, calculate relative mortality risk by combining HRs from all conditions */

/* note that each person appears twice in the data, with identical
conditions but different risk adjustments.  which is why e.g. diabetes
can take on 3 different values instead of 2. */

/* risk_factor is the heightened probability of mortality relative to the reference group
  for this individual. Note that this is a probability multiplier, *not* a multiplier of
  relative risk, odds ratio, or hazard ratio.

  FIX: However, it is calculated by treating the HR as an OR-- this is inconsequential but
       we should do the conversion above anyway just to be precise. */

/* create combined discrete age risk factors */
gen hr_full_age_discrete = hr_full_age18_40 * hr_full_age40_50 * hr_full_age50_60 * hr_full_age60_70 * hr_full_age70_80 * hr_full_age80_
gen hr_age_sex_age_discrete = hr_age_sex_age18_40 * hr_age_sex_age40_50 * hr_age_sex_age50_60 * hr_age_sex_age60_70 * hr_age_sex_age70_80 * hr_age_sex_age80_

/* drop the individual age vars to avoid confusion */
drop *40* *60* *80*

/* rename "age_sex" to "simple" so i don't get confused by these repeated words */
ren *age_sex* *simple*

/* age only */
gen rf_full_age_d = hr_full_age_discrete
gen rf_full_age_c = hr_full_age_cts
gen rf_simple_age_d = hr_simple_age_discrete
gen rf_simple_age_c = hr_simple_age_cts

/* age and sex */
gen rf_full_agesex_d = hr_full_age_discrete * hr_full_male
gen rf_full_agesex_c = hr_full_age_cts * hr_full_male
gen rf_simple_agesex_d = hr_simple_age_discrete * hr_simple_male
gen rf_simple_agesex_c = hr_simple_age_cts * hr_simple_male

/* create a factor combining conditions with biomarkers */
gen rf_full_biomarkers = 1
foreach condition in $hr_biomarker_vars {
  replace rf_full_biomarkers = rf_full_biomarkers * hr_full_`condition'
}

/* generate fully adjusted DLHS model */
gen rf_full_d = rf_full_agesex_d * rf_full_biomarkers
gen rf_full_c = rf_full_agesex_c * rf_full_biomarkers

/* collapse the data to 1 combined risk factor for each age */
collapse (mean) rf_* $hr_biomarker_vars $hr_selfreport_vars [aw=wt], by(age)
save $tmp/foo, replace

/* bring in the NHS hazard ratios so we can calculate combined risk using aggregate data */
gen v1 = 0
merge m:1 v1 using $tmp/uk_nhs_hazard_ratios_flat_hr_full, nogen
merge m:1 v1 using $tmp/uk_nhs_hazard_ratios_flat_hr_age_sex, nogen
merge m:1 age using $tmp/uk_age_predicted_hr, keep(match master) nogen

/* bring in some GBD prevalence data */
merge m:1 age using $health/gbd/gbd_nhs_conditions_india, keep(match master) nogen

/* bring in NY odds ratios */
merge m:1 age using $tmp/nystate_or, keep(match master) nogen

/* ***** CREATE FULLY-ADJUSTED CONTINUOUS RISK HAZARD MODEL */
/* assume 47% men for now in both simple and full models */
gen arisk_full = hr_full_age_cts * (male_hr_full * .47 + .53)
foreach v in $hr_biomarker_vars {
  replace arisk_full = arisk_full * ( (`v'_hr_full * `v') + (1 - `v'))
}

/* **** CREATE AGGREGATE RISK FROM SIMPLE MODEL */
gen arisk_simple = hr_age_sex_age_cts * (male_hr_age_sex * .47 + .53)

/* label micro data and aggregate risk models */
label var arisk_simple "aggregate age-sex only (simple) model"
label var arisk_full   "aggregate fully adjusted model"
label var rf_simple_agesex_c "microdata age-sex only (simple) model"
label var rf_full_c "microdata fully adjusted model"


/* **************** CREATE THE DLHS BIOMARKER + GBD EVERYTHING ELSE MODEL */
/* stick to 47% male for consistency with DLHS */
gen arisk_gbd = hr_full_age_cts * (male_hr_full * .47 + .53)

/* add in biomarkers */
foreach v in $hr_biomarker_vars {
  replace arisk_gbd = arisk_gbd * ( (`v'_hr_full * `v') + (1 - `v'))
}
/* add in GBD vars */
foreach v in $hr_gbd_vars {
  replace arisk_gbd = arisk_gbd * ( (`v'_hr_full * gbd_`v') + (1 - gbd_`v'))
}
label var arisk_gbd "aggregate biomarker + GBD model"

/* **** CREATE A FULLY ADJUSTED MODEL using NY odds ratios instead of NHS */
gen arisk_ny = arisk_full
foreach v in bp_high diabetes_uncontr chronic_heart_dz kidney_dz chronic_resp_dz {

  /* divide out the old aggregate effect */
  replace arisk_ny = arisk_ny / ( (`v'_hr_full * `v') + (1 - `v'))

  /* multiply in the age-specific NY version */
  replace arisk_ny = arisk_ny * ( (ny_or_`v' * `v') + (1 - `v'))
}
label var arisk_ny "full w/NY age-specific ORs for major conditions"

/* save a temporary version of the data */
save $tmp/aggs, replace

/* compare microdata risk factor to aggregate risk factor models */
sc arisk_full rf_full_c arisk_simple rf_simple_agesex_c, name(agg_v_micro)

/* 3 models: 1. agesex; 2. biomarkers; 3. biomarker + GBD   */
sc arisk_simple arisk_full arisk_gbd, name(3models)

/* compare full model to NY OR model */
sc arisk_full arisk_ny, name(vs_ny)

/* list the mortality predictions so we can report the expected %
   change in mortality from switching models */
list age arisk_simple arisk_full arisk_gbd

save $tmp/india_models, replace

/**********************************************************************/
/* decompose risk factors to see which raise india mortality the most */
/**********************************************************************/
use $tmp/aggs, clear

/* put age group vars back in so we can risk adjust with them */
gen age18_40 = inrange(age, 18, 39)
gen age40_50 = inrange(age, 40, 50)
gen age50_60 = inrange(age, 50, 60)
gen age60_70 = inrange(age, 60, 70)
gen age70_80 = inrange(age, 70, 80)
gen age80_   = inrange(age, 80, 100)
gen male     = 0.52

/* bring in india population */
merge 1:1 age using $tmp/india_pop, keep(match master)
keep if _merge == 3
drop _merge

/* calculate population share of each group */
sum india_pop
gen total_pop = `r(mean)' * `r(N)'
gen pop_share = india_pop / total_pop

/* multiple risk factor by prevalence to get increased mortality risk from this condition at each age */
foreach v in $age_vars male $hr_biomarker_vars {
  gen age_risk_full_`v' = ( (`v'_hr_full * `v') + (1 - `v'))
}
foreach v in $hr_gbd_vars {
  gen age_risk_full_`v' = ( (`v'_hr_full * gbd_`v') + (1 - gbd_`v'))
}

/* now multiply each risk factor contribution by the population share */
foreach v in $age_vars male $hr_gbd_vars $hr_biomarker_vars {

  /* calculate contribution to aggregate risk at each age */
  gen pop_risk_fpart_`v' = age_risk_full_`v' * pop_share
  
  /* add it up across all ages */
  bys v1: egen pop_risk_full_`v' = total(pop_risk_fpart_`v')
}

/* show the aggregate contribution of each risk factor */
foreach v in $age_vars male $hr_gbd_vars $hr_biomarker_vars {
  qui sum pop_risk_full_`v' in 1
  di %20s "`v': " %6.3f `r(mean)'
}

/* REPEAT PROCESS FOR SIMPLE MODEL -- AGE-SEX ONLY */
/* multiple risk factor by prevalence to get increased mortality risk from this condition at each age */
foreach v in $age_vars male  {
  gen age_risk_simple_`v' = ( (`v'_hr_age_sex * `v') + (1 - `v'))
}
foreach v in $age_vars male {

  /* calculate contribution to aggregate risk at each age */
  gen pop_risk_simple_part_`v' = age_risk_simple_`v' * pop_share
  
  /* add it up across all ages */
  bys v1: egen pop_risk_simple_`v' = total(pop_risk_simple_part_`v')
}

/* show the aggregate contribution of each risk factor */
foreach v in $age_vars male  {
  qui sum pop_risk_simple_`v' in 1
  di %20s "`v': " %6.3f `r(mean)'
}

exit

