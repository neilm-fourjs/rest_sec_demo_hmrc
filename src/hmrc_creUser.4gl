IMPORT com

CONSTANT C_SERVER_TOKEN = "ddb5d3f52c6d5e2baaebbf3acf181f9"
CONSTANT C_CON_TIMEOUT = 5
DEFINE m_txt STRING
MAIN
	DEFINE l_data STRING
	OPEN FORM frm FROM "hmrc_test"
	DISPLAY FORM frm

	CALL rest_hmrc2("https://test-api.service.hmrc.gov.uk/hello/application", C_SERVER_TOKEN, NULL )

	LET l_data = '
{
  "serviceNames": [
    "corporation-tax",
    "paye-for-employers",
    "submit-vat-returns",
    "national-insurance",
    "self-assessment",
    "mtd-income-tax",
    "mtd-vat",
    "lisa",
    "secure-electronic-transfer",
    "relief-at-source",
    "customs-services"
  ]
}'
	CALL rest_hmrc2("https://test-api.service.hmrc.gov.uk/create-test-user/organisations", C_SERVER_TOKEN, l_data )

	CALL disp( "Finished." )
	MENU "Finished"
		ON ACTION close EXIT MENU
		ON ACTION exit EXIT MENU
	END MENU
END MAIN
--------------------------------------------------------------------------------
FUNCTION rest_hmrc2( l_url STRING, l_token STRING, l_data STRING )
	DEFINE l_req com.HttpRequest
	DEFINE l_resp com.HTTPResponse
	DEFINE l_info RECORD
		status SMALLINT,
		header STRING
	END RECORD

	CALL disp("URL:"||l_url)
	LET l_req = com.HttpRequest.Create(l_url)
	IF l_data IS NULL THEN
		CALL l_req.setMethod("GET")
	ELSE
		CALL l_req.setMethod("POST")
	END IF
	CALL l_req.setHeader("Content-Type", "application/json")
	CALL l_req.setHeader("Accept", "application/vnd.hmrc.1.0+json")
	CALL l_req.setHeader("Gov-Test-Scenario","-")

	CALL disp("Setting Time Out "||C_CON_TIMEOUT)
	CALL l_req.setConnectionTimeOut( C_CON_TIMEOUT )

	IF l_token IS NOT NULL THEN
		CALL l_req.setHeader("Authorization", "Bearer "||l_token)
	END IF

	IF l_data IS NULL THEN
		CALL disp("doing doRequest ...")
		TRY
			CALL l_req.doRequest()
		CATCH
			CALL disp( "Failed to doRequest for "||l_url||" "||STATUS||" "||ERR_GET(STATUS) )
			RETURN
		END TRY
	ELSE
		CALL disp("doing doTextRequest ...")
		TRY
			CALL l_req.doTextRequest(l_data)
		CATCH
			CALL disp( "Failed to doTextRequest for "||l_url||" "||STATUS||" "||ERR_GET(STATUS) )
			RETURN
		END TRY
	END IF

	CALL disp("doing getResponse ...")
	TRY
		LET l_resp = l_req.getResponse()
	CATCH
		CALL disp( "Failed to getResponse for "||l_url||" "||STATUS||" "||ERR_GET(STATUS) )
		RETURN
	END TRY

	CALL disp("getting Status ...")
	LET l_info.status = l_resp.getStatusCode()
	IF l_info.status != 200 THEN
		CALL disp( "Failed:"||l_info.status)
--		RETURN
	ELSE
		CALL disp( "Success!" )
	END IF

	LET l_info.header = l_resp.getHeader("Content-Type")
	CALL disp( "StatusCode:"||l_info.status )
	CALL disp( "Header:"||l_info.header )
	CALL disp( "Response:"||l_resp.getTextResponse() )
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION disp(l_txt STRING)
	DISPLAY l_txt
	LET m_txt = m_txt.append( CURRENT||":"||l_txt||"\n" )
	DISPLAY BY NAME m_txt
	CALL ui.Interface.refresh()
END FUNCTION