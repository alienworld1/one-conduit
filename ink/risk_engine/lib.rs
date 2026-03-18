#![cfg_attr(not(feature = "std"), no_std, no_main)]

#[ink::contract]
mod risk_oracle {
    use ink::storage::Mapping;

    #[ink(storage)]
    pub struct RiskOracle {
        scores: Mapping<u128, u128>,
        owner: ink::primitives::H160,
    }

    #[ink(event)]
    pub struct ScoreUpdated {
        #[ink(topic)]
        product_id: ink::U256,
        new_score: ink::U256,
    }

    impl RiskOracle {
        #[ink(constructor, default)]
        pub fn new() -> Self {
            Self {
                scores: Mapping::default(),
                owner: Self::env().caller(),
            }
        }

        #[ink(message)]
        pub fn getScore(&self, product_id: ink::U256) -> ink::U256 {
            // as_u128() panics for keccak256-sized values. low_u128() truncates safely.
            let id: u128 = product_id.low_u128();
            let score = self.scores.get(&id).unwrap_or(0);
            ink::U256::from(score)
        }

        #[ink(message)]
        pub fn updateScore(
            &mut self,
            product_id: ink::U256,
            apy_bps: ink::U256,
            tvl_usd: ink::U256,
            utilization_bps: ink::U256,
            contract_age_days: ink::U256,
        ) -> Result<ink::U256, ()> {
            if self.env().caller() != self.owner {
                return Err(());
            }

            let id: u128 = product_id.low_u128();
            let apy = apy_bps.low_u128();
            let tvl = tvl_usd.low_u128();
            let util = utilization_bps.low_u128();
            let age = contract_age_days.low_u128();

            // Utilisation
            let util_score = 100u128.saturating_sub(util.saturating_mul(100) / 10_000);
            let util_weighted = util_score * 40 / 100;

            // TVL
            let tvl_score = core::cmp::min(100, tvl.saturating_mul(100) / 10_000_000);
            let tvl_weighted = tvl_score * 35 / 100;

            // Maturity
            let maturity_score = core::cmp::min(100, age.saturating_mul(100) / 180);
            let maturity_weighted = maturity_score * 15 / 100;

            // APY
            let apy_score = if apy <= 2000 {
                100
            } else if apy >= 10_000 {
                0
            } else {
                100u128.saturating_sub((apy - 2000) * 100 / 8_000)
            };
            let apy_weighted = apy_score * 10 / 100;

            let final_score = core::cmp::min(
                100,
                util_weighted + tvl_weighted + maturity_weighted + apy_weighted,
            );

            self.scores.insert(&id, &final_score);

            let new_score = ink::U256::from(final_score);
            self.env().emit_event(ScoreUpdated {
                product_id,
                new_score,
            });

            Ok(new_score)
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[ink::test]
        fn test_scoring() {
            let mut contract = RiskOracle::new();
            
            // `updateScore(1, 500, 5000000, 5000, 180)` returns `62` (+-1)
            let result = contract.updateScore(
                ink::U256::from(1),
                ink::U256::from(500),
                ink::U256::from(5000000),
                ink::U256::from(5000),
                ink::U256::from(180),
            ).unwrap();

            assert_eq!(result, ink::U256::from(62));
            assert_eq!(contract.getScore(ink::U256::from(1)), ink::U256::from(62));
            assert_eq!(contract.getScore(ink::U256::from(2)), ink::U256::from(0));
            
            let low = contract.updateScore(
                ink::U256::from(1),
                ink::U256::from(15000),
                ink::U256::from(0),
                ink::U256::from(9500),
                ink::U256::from(0),
            ).unwrap();
            assert_eq!(low, ink::U256::from(2));

            let high = contract.updateScore(
                ink::U256::from(1),
                ink::U256::from(100),
                ink::U256::from(10000000),
                ink::U256::from(100),
                ink::U256::from(200),
            ).unwrap();
            assert_eq!(high, ink::U256::from(99));
        }

        #[ink::test]
        fn test_unauthorized() {
            let mut contract = RiskOracle::new();
            
            let accounts = ink::env::test::default_accounts();
            ink::env::test::set_caller(accounts.bob);

            let result = contract.updateScore(
                ink::U256::from(1),
                ink::U256::from(500),
                ink::U256::from(5000000),
                ink::U256::from(5000),
                ink::U256::from(180),
            );

            assert_eq!(result, Err(()));
        }
    }
}
