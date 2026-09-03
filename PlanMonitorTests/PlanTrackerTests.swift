//
//  PlanTrackerTests.swift
//  PlanTrackerTests
//
//  Copyright © 2025 Intelligent Computing OU. All rights reserved.
//

import Foundation
import Testing
@testable import PlanTracker

struct PlanTrackerTests {

    @Test func oneCentPrepaidResidueIsHidden() {
        let usage = makeUsageData(
            prepaidCreditsRemaining: 1,
            prepaidCreditsTotal: 1,
            prepaidCreditsCurrency: "USD",
            prepaidAutoReloadEnabled: false,
            overageMonthlyLimit: 500,
            overageUsedCredits: 0,
            overageCurrency: "USD",
            overageEnabled: true
        )

        #expect(usage.hasAvailablePrepaidCredits == false)
        #expect(usage.prepaidCreditsRemainingFormatted == nil)
        #expect(usage.prepaidCreditsTotalFormatted == nil)
        #expect(usage.prepaidCreditsSpentFormatted == nil)
        #expect(usage.prepaidCreditsUtilization == nil)
    }

    @Test func promotionalCreditBecomesVisibleAtTwentyCents() {
        let usage = makeUsageData(
            prepaidCreditsRemaining: 20,
            prepaidCreditsTotal: nil,
            prepaidCreditsCurrency: "USD",
            overageMonthlyLimit: nil,
            overageUsedCredits: 0,
            overageCurrency: "USD",
            overageEnabled: false
        )

        #expect(usage.hasAvailablePrepaidCredits == true)
        #expect(usage.prepaidCreditsRemainingFormatted == "0.20 USD")
        #expect(usage.prepaidCreditsUtilization == 0)
    }

    @Test func nineteenCentCreditDustIsHiddenForBothBuckets() {
        let promotional = makeUsageData(
            prepaidCreditsRemaining: 19,
            prepaidCreditsTotal: 20000,
            prepaidCreditsCurrency: "USD",
            overageMonthlyLimit: nil,
            overageUsedCredits: 0,
            overageCurrency: "USD",
            overageEnabled: false
        )
        let paid = makeUsageData(
            prepaidCreditsRemaining: nil,
            prepaidCreditsTotal: nil,
            prepaidCreditsCurrency: nil,
            paidCreditsRemaining: 19,
            paidCreditsTotal: 1000,
            paidCreditsCurrency: "USD",
            overageMonthlyLimit: nil,
            overageUsedCredits: 0,
            overageCurrency: "USD",
            overageEnabled: false
        )

        #expect(promotional.hasAvailablePrepaidCredits == false)
        #expect(paid.hasAvailablePaidCredits == false)
    }

    @Test func usageCreditCapIsTrackedEvenWhenThePrepaidResidueIsHidden() {
        let usage = makeUsageData(
            prepaidCreditsRemaining: 1,
            prepaidCreditsTotal: 1,
            prepaidCreditsCurrency: "USD",
            overageMonthlyLimit: 500,
            overageUsedCredits: 125,
            overageCurrency: "USD",
            overageEnabled: true
        )

        #expect(usage.hasStartedExtraUsageSpend == true)
        #expect(usage.overageUsedFormatted == "1.25 USD")
        #expect(usage.overageUtilization == 25)
    }

    @Test func prepaidBalanceWithoutGrantTotalStillHasProgressDenominator() {
        let usage = makeUsageData(
            prepaidCreditsRemaining: 20001,
            prepaidCreditsTotal: nil,
            prepaidCreditsCurrency: "USD",
            overageMonthlyLimit: nil,
            overageUsedCredits: 0,
            overageCurrency: "USD",
            overageEnabled: true
        )

        #expect(usage.hasAvailablePrepaidCredits == true)
        #expect(usage.prepaidCreditsRemainingFormatted == "200.01 USD")
        #expect(usage.prepaidCreditsTotalFormatted == "200.01 USD")
        #expect(usage.prepaidCreditsSpentFormatted == "0.00 USD")
        #expect(usage.prepaidCreditsUtilization == 0)
    }

    @Test func freeCreditBalanceDoesNotInventConsumptionFromSpendCounter() {
        let usage = makeUsageData(
            prepaidCreditsRemaining: 19501,
            prepaidCreditsTotal: nil,
            prepaidCreditsCurrency: "USD",
            overageMonthlyLimit: 500,
            overageUsedCredits: 500,
            overageCurrency: "USD",
            overageEnabled: true
        )

        #expect(usage.prepaidCreditsTotalFormatted == "195.01 USD")
        #expect(usage.prepaidCreditsSpentFormatted == "0.00 USD")
        #expect(usage.hasStartedExtraUsageSpend == true)
        #expect(usage.overageUsedFormatted == "5.00 USD")
        #expect(usage.overageUtilization == 100)
    }

    @Test func promotionalCreditBalanceAndUsageCapAreSeparateDimensions() {
        let usage = makeUsageData(
            prepaidCreditsRemaining: 18132,
            prepaidCreditsTotal: 20000,
            prepaidCreditsCurrency: "USD",
            overageMonthlyLimit: 500,
            overageUsedCredits: 19,
            overageCurrency: "USD",
            overageEnabled: true
        )

        #expect(usage.prepaidCreditsRemainingFormatted == "181.32 USD")
        #expect(usage.prepaidCreditsSpentFormatted == "18.68 USD")
        #expect(usage.hasStartedExtraUsageSpend == true)
        #expect(usage.overageUsedFormatted == "0.19 USD")
        #expect(usage.overageUtilization == 3.8)
    }

    @Test func storedPrepaidCreditsUseMinorUnitsExactly() {
        let usage = makeUsageData(
            prepaidCreditsRemaining: nil,
            prepaidCreditsTotal: nil,
            prepaidCreditsCurrency: nil,
            prepaidAutoReloadEnabled: false,
            paidCreditsRemaining: 11331,
            paidCreditsTotal: 11331,
            paidCreditsCurrency: "USD",
            overageMonthlyLimit: 20000,
            overageUsedCredits: 0,
            overageCurrency: "USD",
            overageEnabled: true
        )

        #expect(usage.hasAvailablePaidCredits == true)
        #expect(usage.paidCreditsRemainingFormatted == "113.31 USD")
        #expect(usage.paidCreditsTotalFormatted == "113.31 USD")
        #expect(usage.paidCreditsSpentValueFormatted == "0.00")
    }

    @Test func invoiceGaugeRequiresMoreThanOneCent() {
        let hidden = makeUsageData(
            prepaidCreditsRemaining: nil,
            prepaidCreditsTotal: nil,
            prepaidCreditsCurrency: nil,
            pendingInvoiceAmount: 1,
            overageMonthlyLimit: 20000,
            overageUsedCredits: 0,
            overageCurrency: "USD",
            overageEnabled: true
        )
        let visible = makeUsageData(
            prepaidCreditsRemaining: nil,
            prepaidCreditsTotal: nil,
            prepaidCreditsCurrency: nil,
            pendingInvoiceAmount: 125,
            overageMonthlyLimit: 20000,
            overageUsedCredits: 0,
            overageCurrency: "USD",
            overageEnabled: true
        )

        #expect(hidden.pendingInvoiceFormatted == nil)
        #expect(visible.pendingInvoiceFormatted == "1.25 USD")
        #expect(visible.pendingInvoiceUtilization == 0.625)
    }

    @Test func claudeUsageDecodesDisabledExtraSpendControlObject() throws {
        let json = """
        {
          "five_hour": {
            "utilization": 22.0,
            "resets_at": "2026-07-09T14:30:00.039431+00:00"
          },
          "seven_day": {
            "utilization": 84.0,
            "resets_at": "2026-07-10T04:00:00.039459+00:00"
          },
          "extra_usage": {
            "is_enabled": false,
            "monthly_limit": null,
            "used_credits": null,
            "utilization": null,
            "currency": null,
            "decimal_places": null
          },
          "limits": [
            {
              "kind": "weekly_scoped",
              "group": "weekly",
              "percent": 99,
              "resets_at": "2026-07-10T04:00:00.039948+00:00",
              "scope": {
                "model": {
                  "id": null,
                  "display_name": "Fable"
                },
                "surface": null
              },
              "is_active": true
            }
          ],
          "spend": {
            "used": {
              "amount_minor": 0,
              "currency": "USD",
              "exponent": 2
            },
            "limit": null,
            "percent": 0,
            "severity": "normal",
            "enabled": false,
            "cap": null,
            "balance": null,
            "auto_reload": null
          }
        }
        """

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(UsageResponse.self, from: Data(json.utf8))

        #expect(response.extraUsage == nil)
        #expect(response.extraUsageEnabled == false)
        #expect(response.spend?.enabled == false)
        #expect(response.spend?.limit == nil)
        #expect(response.sevenDayScoped?.label == "Fable")
        #expect(response.sevenDayScoped?.period.utilization == 99)
    }

    @Test func prepaidCreditsDecodePromotionalTrancheWithoutSynthesizingTotal() throws {
        let json = """
        {
          "amount": 18134,
          "currency": "USD",
          "balance_credits": 199,
          "auto_reload_settings": null,
          "pending_invoice_amount_cents": null,
          "tranches": [],
          "promo_tranches": [
            {
              "remaining_amount_minor_units": 18132,
              "currency": "USD",
              "granted_amount_minor_units": 20000
            }
          ]
        }
        """

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(PrepaidCreditsResponse.self, from: Data(json.utf8))

        #expect(response.amount == 18134)
        #expect(response.promoTranches?.count == 1)
        #expect(response.promoTranches?.first?.grantedAmountMinorUnits == 20000)
        #expect(response.promoTranches?.first?.remainingAmountMinorUnits == 18132)
        #expect(response.pendingInvoiceAmountCents == nil)
    }

    private func makeUsageData(
        prepaidCreditsRemaining: Int?,
        prepaidCreditsTotal: Int?,
        prepaidCreditsCurrency: String?,
        prepaidAutoReloadEnabled: Bool? = nil,
        paidCreditsRemaining: Int? = nil,
        paidCreditsTotal: Int? = nil,
        paidCreditsCurrency: String? = nil,
        pendingInvoiceAmount: Int? = nil,
        overageMonthlyLimit: Int?,
        overageUsedCredits: Int?,
        overageCurrency: String?,
        overageEnabled: Bool?
    ) -> ClaudeUsageData {
        ClaudeUsageData(
            fiveHourUtilization: nil,
            fiveHourResetsAt: nil,
            sevenDayUtilization: nil,
            sevenDayResetsAt: nil,
            sevenDayOpusUtilization: nil,
            sevenDayOpusResetsAt: nil,
            sevenDaySonnetUtilization: nil,
            sevenDaySonnetResetsAt: nil,
            sevenDayScopedLabel: nil,
            sevenDayScopedUtilization: nil,
            sevenDayScopedResetsAt: nil,
            extraUsageUtilization: nil,
            extraUsageResetsAt: nil,
            planTier: .max,
            planDisplayNameOverride: "Max (20x)",
            prepaidCreditsRemaining: prepaidCreditsRemaining,
            prepaidCreditsTotal: prepaidCreditsTotal,
            prepaidCreditsCurrency: prepaidCreditsCurrency,
            prepaidCreditsArePromotional: nil,
            prepaidAutoReloadEnabled: prepaidAutoReloadEnabled,
            paidCreditsRemaining: paidCreditsRemaining,
            paidCreditsTotal: paidCreditsTotal,
            paidCreditsCurrency: paidCreditsCurrency,
            pendingInvoiceAmount: pendingInvoiceAmount,
            overageMonthlyLimit: overageMonthlyLimit,
            overageUsedCredits: overageUsedCredits,
            overageCurrency: overageCurrency,
            overageEnabled: overageEnabled,
            overageOutOfCredits: nil
        )
    }
}
