
IMPORT util

FUNCTION hello(l_url STRING, l_token STRING)
	DEFINE l_res_data STRING
	DEFINE l_stat SMALLINT
	CALL rest_hmrc_get( SFMT("%1/hello/user",l_url), l_token) RETURNING l_stat, l_res_data
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION obligations(l_url STRING, l_token STRING)
	DEFINE l_res_data STRING
	DEFINE l_stat SMALLINT
	DEFINE l_vatno STRING
	DEFINE l_from,  l_to DATE
	DEFINE l_status CHAR(1)

	LET l_vatno = "666260217"
	LET l_from = "2017-04-06"
	LET l_to = "2018-04-05"
	LET l_status = "O"

	LET int_flag = FALSE
	INPUT BY NAME l_vatno, l_from, l_to, l_status WITHOUT DEFAULTS
	IF int_flag THEN LET int_flag = FALSE RETURN END IF

	CALL rest_hmrc_get(
	 SFMT("%1/organisations/vat/%2/obligations?from=%3&to=%4&status=%5",l_url,l_vatno, l_from, l_to, l_status), l_token)
		 RETURNING l_stat, l_res_data
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION returns(l_url STRING, l_token STRING)
	DEFINE l_req_data, l_res_data STRING
	DEFINE l_stat SMALLINT
	DEFINE l_vatno, l_period STRING

	LET l_vatno = "666260217"
	LET l_period = "#001"

	LET int_flag = FALSE
	INPUT BY NAME l_vatno, l_period WITHOUT DEFAULTS
	IF int_flag THEN LET int_flag = FALSE RETURN END IF

	LET l_req_data = submit_vat(l_period)
	CALL rest_hmrc_post( 
		SFMT("%1/organisations/vat/%2/returns", l_url, l_vatno) , l_req_data, l_token )
		 RETURNING l_stat, l_res_data
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION submit_vat(l_period STRING) RETURNS STRING
	DEFINE l_ret STRING
	DEFINE l_rec RECORD
		periodKey STRING,
		vatDueSales DECIMAL(12,2),
		vatDueAcquisitions DECIMAL(12,2),
		totalVatDue DECIMAL(12,2),
		vatReclaimedCurrPeriod DECIMAL(12,2),
		netVatDue DECIMAL(12,2),
		totalValueSalesExVAT INTEGER,
		totalValuePurchasesExVAT INTEGER,
		totalValueGoodsSuppliedExVAT INTEGER,
		totalAcquisitionsExVAT INTEGER,
		finalised BOOLEAN
		END RECORD

	LET l_rec.periodKey =  l_period
	LET l_rec.vatDueSales = 100
	LET l_rec.vatDueAcquisitions = 100
	LET l_rec.totalVatDue = 200
	LET l_rec.vatReclaimedCurrPeriod = 100
	LET l_rec.netVatDue = 100
	LET l_rec.totalValueSalesExVat = 500
	LET l_rec.totalValuePurchasesExVAT = 500
	LET l_rec.totalValueGoodsSuppliedExVAT = 500
	LET l_rec.totalAcquisitionsExVAT = 500
	LET l_rec.finalised = FALSE

	LET l_ret = util.JSON.stringify( l_rec )

	RETURN l_ret
END FUNCTION
--------------------------------------------------------------------------------