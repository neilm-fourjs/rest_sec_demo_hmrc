-- Demo program for HMRC Restful calls.
--
-- Arg1: RESET = drop and re-create tables.

IMPORT util
IMPORT os
IMPORT FGL hmrcLib
IMPORT FGL hmrcRest

&include "hmrcLib.inc"

DEFINE m_orgs DYNAMIC ARRAY OF t_hmrcOrganisations
DEFINE m_toks DYNAMIC ARRAY OF t_hmrcAccessToken
DEFINE m_arr DYNAMIC ARRAY OF RECORD
	userId       VARCHAR(30),
	userFullName VARCHAR(100),
	emailAddress VARCHAR(200),
	org_name     VARCHAR(20),
	vrn          VARCHAR(20),
	stat         CHAR(1)
END RECORD
DEFINE m_getTokenURL STRING
DEFINE m_clientId, m_secretId, m_scope STRING
DEFINE m_hmrc_url STRING
DEFINE m_cur_vatNo                                    STRING
DEFINE m_access_token STRING
DEFINE m_access_token_exp DATETIME YEAR TO SECOND
TYPE t_callBack_func FUNCTION(l_data STRING)
MAIN
	DEFINE l_orgno    SMALLINT
	DEFINE l_callBack t_callBack_func

	LET m_getTokenURL = fgl_getEnv("GRANTURL")
	LET m_clientId    = fgl_getEnv("CLIENT_PUBLIC_ID")
	LET m_secretId    = fgl_getEnv("CLIENT_SECRET_ID")
    LET m_hmrc_url    = fgl_getEnv("HMRC_URL")
	LET m_scope       = "hello read:vat write:vat"
    IF m_clientId IS NULL THEN
        CALL getLocalSecrets() RETURNING m_clientId, m_secretId
    END IF
    --DISPLAY SFMT("ClientID: %1 SecretID: %2", m_clientId, m_secretId)

	OPEN FORM hmrcDemo FROM "hmrcDemo"
	DISPLAY FORM hmrcDemo

    DISPLAY "Time: ", CURRENT
	IF NOT connectToDB() THEN
		CALL fgl_winMessage("Error", hmrcLib.m_db_err, "exclamation")
		EXIT PROGRAM
	END IF
	CALL chkTables()

	CALL setupOrganisationArray()

-- Load test json files from disk
	IF m_orgs.getLength() = 0 THEN
		LET l_callBack = FUNCTION newOrganisationFromJson
		CALL loadFromJson(os.path.join(fgl_getEnv("BASE"), "org1.json"), l_callBack)
		LET l_callBack = FUNCTION newObligationsFromJson
		CALL loadFromJson(os.path.join(fgl_getEnv("BASE"), "obl1.json"), l_callBack)
	END IF

	CALL setupScreenArray()

	DISPLAY ARRAY m_arr TO arr.* ATTRIBUTES(ACCEPT = FALSE, CANCEL = FALSE, UNBUFFERED)
		BEFORE ROW
			LET l_orgno     = arr_curr()
			LET m_cur_vatNo = m_orgs[l_orgno].vrn
            CALL uiUpdate(DIALOG, l_orgno)

		ON ACTION getacctok
			IF getAccessTokenFromHMRC() THEN
            END IF

        ON ACTION hellotest
            CALL hellotest()

        ON ACTION mantoken
            CALL getManualToken(l_orgno, TRUE)
		    CALL uiUpdate(DIALOG, l_orgno)

        ON ACTION clrtoken
            CALL getManualToken(l_orgno, FALSE)
		    CALL uiUpdate(DIALOG, l_orgno)

		ON ACTION refreshok
			CALL refreshTokenFromHMRC(l_orgno)
			DISPLAY BY NAME m_toks[l_orgno].token, m_toks[l_orgno].token_expires

		ON ACTION gettok
			CALL newTokenFromHMRC(l_orgno)

		ON ACTION gettok_wc
			CALL newTokenFromHMRC_wc(l_orgno)

		ON ACTION neworg
			CALL newOrganisationFromHMRC()

		ON ACTION obligations
			CALL newObligationsFromHMRC(l_orgno)

		ON ACTION quit
			EXIT DISPLAY
		ON ACTION close
			EXIT DISPLAY
	END DISPLAY
END MAIN
--------------------------------------------------------------------------------
-- screen setup
FUNCTION uiUpdate(d ui.Dialog, l_orgno SMALLINT)
    DISPLAY BY NAME m_orgs[l_orgno].userId, m_orgs[l_orgno].password
    DISPLAY BY NAME m_toks[l_orgno].token, m_toks[l_orgno].token_expires, m_toks[l_orgno].refresh_token
    DISPLAY "" TO l_url
    CALL d.setActionActive("gettok", FALSE)
    CALL d.setActionActive("gettok_wc", FALSE)
    CALL d.setActionActive("refreshok", FALSE)
    CALL d.setActionActive("neworg", TRUE)
    CALL d.setActionActive("obligations", TRUE)
    IF m_arr[l_orgno].stat MATCHES "[NE]" THEN
        CALL d.setActionActive("gettok", TRUE)
        CALL d.setActionActive("gettok_wc", TRUE)
        CALL d.setActionActive("neworg", FALSE)
        CALL d.setActionActive("obligations", FALSE)
    END IF
    IF m_arr[l_orgno].stat = "E" AND m_toks[l_orgno].refresh_token IS NOT NULL THEN
        CALL d.setActionActive("refreshok", TRUE)
    END IF
END FUNCTION
--------------------------------------------------------------------------------
-- build array of the Organisations
FUNCTION setupOrganisationArray()
	CALL m_orgs.clear()
	DECLARE cur1 CURSOR FOR SELECT * FROM hmrcOrganisations
	FOREACH cur1 INTO m_orgs[m_orgs.getLength() + 1].*
	END FOREACH
	CALL m_orgs.deleteElement(m_orgs.getLength())
END FUNCTION
--------------------------------------------------------------------------------
-- build array for the screen.
FUNCTION setupScreenArray()
	DEFINE x SMALLINT
	CALL m_arr.clear()
	CALL m_toks.clear()
	FOR x = 1 TO m_orgs.getLength()
		LET m_arr[x].userId       = m_orgs[x].userId
		LET m_arr[x].emailAddress = m_orgs[x].emailAddress
		LET m_arr[x].org_name     = m_orgs[x].org_name
		LET m_arr[x].userFullName = m_orgs[x].userFullName
		LET m_arr[x].vrn          = m_orgs[x].vrn
		CALL getTokenForOrgFromDB(x)
	END FOR
END FUNCTION
--------------------------------------------------------------------------------
-- try the hello test.
FUNCTION hellotest()
    DEFINE l_url, l_data STRING
	DEFINE l_stat        SMALLINT
    DEFINE l_res RECORD
        message STRING
    END RECORD
    LET l_url = SFMT("%1/hello/application", m_hmrc_url )
    IF m_access_token IS NULL OR CURRENT > m_access_token_exp THEN
        IF NOT getAccessTokenFromHMRC() THEN
        END IF
    END IF
	CALL hmrcRest.request(l_url, m_access_token, NULL) RETURNING l_stat, l_data
    IF l_stat = 200 THEN
        CALL util.JSON.parse(l_data, l_res)
        CALL fgl_winMessage("Success", l_res.message, "information")
    END IF
    DISPLAY SFMT("Hello: %1 - %2", l_stat, l_data)
END FUNCTION
--------------------------------------------------------------------------------
-- get Access token
FUNCTION getAccessTokenFromHMRC() RETURNS BOOLEAN
	DEFINE l_req_data, l_data, l_url STRING
	DEFINE l_stat SMALLINT
	DEFINE l_rec RECORD
		access_token STRING,
		scope        STRING,
		expires_in   FLOAT,
		token_type   STRING
	END RECORD

    LET l_url = SFMT("%1/oauth/token", m_hmrc_url)
	LET l_req_data =
			SFMT("client_secret=%1&client_id=%2&grant_type=client_credentials&scope=%3", m_secretId, m_clientId, m_scope)

	CALL hmrcRest.request(l_url, NULL, l_req_data) RETURNING l_stat, l_data
	IF l_stat > 300 THEN
		CALL hmrcLib.errDisp2("Failed! " || l_stat, m_hmrc_url, l_data)
		RETURN FALSE
	END IF
	TRY
		CALL hmrcLib.disp(l_data)
		CALL util.JSON.parse(l_data, l_rec)
		CALL hmrcLib.disp(SFMT("Access Token: %1", l_rec.access_token))
	CATCH
		CALL hmrcLib.disp("JSON Parse failed!")
		RETURN FALSE
	END TRY
    LET m_access_token = l_rec.access_token
    LET m_access_token_exp = CURRENT + ( l_rec.expires_in UNITS SECOND )
    RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------
-- manually override the current token - TESTING ONLY!
FUNCTION getManualToken(l_orgno SMALLINT, l_ask BOOLEAN)
    DEFINE l_srv_token STRING
    LET m_arr[l_orgno].stat = "N"
    LET m_toks[l_orgno].token = NULL
    LET m_toks[l_orgno].token_expires = NULL
    LET m_toks[l_orgno].token_endpoint = m_getTokenURL
    LET m_toks[l_orgno].refresh_token = NULL
    IF l_ask THEN
        PROMPT "Enter Token: " FOR l_srv_token
        IF int_flag THEN LET int_flag = FALSE RETURN END IF
    ELSE
        RETURN
    END IF
    LET m_arr[l_orgno].stat = "M"
    LET m_toks[l_orgno].token = l_srv_token

END FUNCTION
--------------------------------------------------------------------------------
-- try and get the token for the Organisation from the DB and set the state.
FUNCTION getTokenForOrgFromDB(l_orgno SMALLINT)
    DISPLAY SFMT("getTokenForOrgFromDBGet: for '%1'", m_orgs[l_orgno].vrn)
	SELECT * INTO m_toks[l_orgno].* FROM hmrcAccessTokens WHERE vrn = m_orgs[l_orgno].vrn
	IF STATUS = 0 THEN
		IF m_toks[l_orgno].token_expires > CURRENT THEN
			LET m_arr[l_orgno].stat = "Y" -- valid
		ELSE
			LET m_arr[l_orgno].stat = "E" -- expired
		END IF
	ELSE
		LET m_arr[l_orgno].stat = "N" -- no token
        LET m_toks[l_orgno].token_endpoint = SFMT("%1/oauth/token", m_hmrc_url)
	END IF
    DISPLAY SFMT("getTokenForOrgFromDBGet: %1",  m_arr[l_orgno].stat)
END FUNCTION
--------------------------------------------------------------------------------
-- get the Token by calling oauth program.
FUNCTION newTokenFromHMRC(l_orgno SMALLINT)
	DEFINE l_url STRING
	LET l_url = m_getTokenURL || "?Arg=" || m_orgs[l_orgno].vrn
	DISPLAY BY NAME l_url
	CALL ui.Interface.frontCall("standard", "launchURL", [l_url], [])
	MENU
		COMMAND "Grant Done"
			EXIT MENU
	END MENU

	CALL getTokenForOrgFromDB(l_orgno)
END FUNCTION
--------------------------------------------------------------------------------
-- get the Token by calling oauth program in a WebComponent
FUNCTION newTokenFromHMRC_wc(l_orgno SMALLINT)
	DEFINE l_url STRING
	OPEN WINDOW getToken_wc WITH FORM "getToken_wc"
	LET l_url = m_getTokenURL || "?Arg=" || m_orgs[l_orgno].vrn
	DISPLAY BY NAME m_orgs[l_orgno].userId, m_orgs[l_orgno].password, l_url
	DISPLAY l_url TO wc
	MENU
		COMMAND "Grant Done"
			EXIT MENU
		ON ACTION close
			EXIT MENU
	END MENU
	CALL getTokenForOrgFromDB(l_orgno)
	CLOSE WINDOW getToken_wc
END FUNCTION
--------------------------------------------------------------------------------
-- Refresh the token for the Organisation
FUNCTION refreshTokenFromHMRC(l_orgno SMALLINT)
	DEFINE l_req_data, l_data STRING
	DEFINE l_stat             SMALLINT
	DEFINE l_hmrcToken        t_hmrcAccessToken
	DEFINE l_rec RECORD
		access_token  STRING,
		refresh_token STRING,
		expires_in    FLOAT,
		scope         STRING,
		token_type    STRING
	END RECORD

	LET l_req_data =
			SFMT("client_secret=%1&client_id=%2&grant_type=refresh_token&refresh_token=%3",
					m_secretId, m_clientId, m_toks[l_orgno].refresh_token)
	DISPLAY m_toks[l_orgno].token_endpoint TO l_url
	CALL hmrcRest.request(m_toks[l_orgno].token_endpoint, NULL, l_req_data) RETURNING l_stat, l_data
	IF l_stat > 300 THEN
		CALL hmrcLib.errDisp2("Failed! " || l_stat, m_toks[l_orgno].token_endpoint, l_data)
		RETURN
	END IF
	TRY
		CALL hmrcLib.disp(l_data)
		CALL util.JSON.parse(l_data, l_rec)
		CALL hmrcLib.disp("Refresh New Token:" || l_rec.access_token)
	CATCH
		CALL hmrcLib.disp("JSON Parse failed!")
		RETURN
	END TRY

    LET l_hmrcToken.vrn = m_orgs[l_orgno].vrn
    LET l_hmrcToken.token = l_rec.access_token
    LET l_hmrcToken.token_expires = CURRENT + ( l_rec.expires_in UNITS SECOND )
    LET l_hmrcToken.token_endpoint = m_toks[l_orgno].token_endpoint
	IF NOT hmrcLib.updateTokenInDB(l_hmrcToken.*) THEN
		CALL hmrcLib.errDisp(hmrcLib.m_db_err)
	ELSE
		MESSAGE "Token Registered"
		CALL getTokenForOrgFromDB(l_orgno)
	END IF
END FUNCTION
--------------------------------------------------------------------------------
-- Create a new Test Organisation using the API
FUNCTION newOrganisationFromHMRC()
	DEFINE l_data                      STRING
	DEFINE l_stat                      SMALLINT
	DEFINE l_reply, l_url, l_srv_token STRING
	LET l_url = SFMT("%1/create-test-user/organisations", m_hmrc_url)
	DISPLAY BY NAME l_url
	LET l_srv_token = fgl_getEnv("SERVER_TOKEN")
    IF l_srv_token IS NULL THEN
        PROMPT "Enter Token: " FOR l_srv_token
        IF int_flag THEN LET int_flag = FALSE RETURN END IF
    END IF
	LET l_data      = '
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
	CALL hmrcRest.request(l_url, l_srv_token, l_data) RETURNING l_stat, l_reply
	IF l_stat < 400 THEN
		CALL newOrganisationFromJson(l_reply)
	ELSE
		CALL hmrcLib.errDisp(l_reply)
	END IF
END FUNCTION
--------------------------------------------------------------------------------
-- insert new Organisation into DB if it doesn't already exist.
FUNCTION newOrganisationToDB(l_rec)
	DEFINE l_rec t_hmrcOrganisations
	SELECT * FROM hmrcOrganisations WHERE vrn = l_rec.vrn
	IF STATUS = NOTFOUND THEN
		INSERT INTO hmrcOrganisations VALUES(l_rec.*)
		DISPLAY "Organisation Inserted."
	ELSE
		ERROR "Organisation Exists!"
	END IF
END FUNCTION
--------------------------------------------------------------------------------
-- load example from JSON file
--
-- @param l_fileName filename/path to file with JSON data
-- @param l_callback the function to process the JSON
FUNCTION loadFromJson(l_fileName STRING, l_callBack t_callBack_func)
	DEFINE l_data TEXT
-- read JSON file
	LOCATE l_data IN FILE l_fileName
	CALL l_callBack(l_data)
END FUNCTION
--------------------------------------------------------------------------------
-- new Oranisation JSON data
FUNCTION newOrganisationFromJson(l_data STRING)
	DEFINE l_recJSON t_hmrcOrganisationsJSON
	DEFINE l_rec     t_hmrcOrganisations

-- populate FULL 4gl record from JSON
	CALL util.JSON.parse(l_data, l_recJSON)
-- populate flat 4gl record from JSON
	CALL util.JSON.parse(l_data, l_rec)
-- add missing non-flat fields to flat record.
	LET l_rec.org_name          = l_recJSON.organisationDetails.name
	LET l_rec.org_address_line1 = l_recJSON.organisationDetails.address.line1
	LET l_rec.org_address_line2 = l_recJSON.organisationDetails.address.line2
	LET l_rec.org_address_pcode = l_recJSON.organisationDetails.address.postcode
	IF l_rec.vrn IS NULL THEN
		ERROR "Organisation missing VRN!"
		RETURN
	END IF
	LET m_cur_vatNo = l_rec.vrn
-- add to the array
	LET m_orgs[m_orgs.getLength() + 1].* = l_rec.*

-- insert into DB.
	CALL newOrganisationToDB(l_rec.*)

END FUNCTION
--------------------------------------------------------------------------------
-- get Obligations from the HMRC for the Organisation
FUNCTION newObligationsFromHMRC(l_orgno SMALLINT)
	DEFINE l_url, l_reply STRING
	DEFINE l_stat         SMALLINT
	DEFINE l_vatno        STRING
	DEFINE l_from, l_to   DATE
	DEFINE l_status       CHAR(1)

	LET l_vatno  = m_orgs[l_orgno].vrn
	LET l_from   = "2018-04-06"
	LET l_to     = "2019-04-05"
	LET l_status = "O"

	LET int_flag = FALSE
	INPUT BY NAME l_from, l_to, l_status WITHOUT DEFAULTS
	IF int_flag THEN
		LET int_flag = FALSE
		RETURN
	END IF

	LET l_url =
			SFMT("%1/organisations/vat/%2/obligations?from=%3&to=%4&status=%5",
					m_hmrc_url, l_vatno, l_from, l_to, l_status)
	DISPLAY BY NAME l_url
	CALL hmrcRest.request(l_url, m_toks[l_orgno].token, "") RETURNING l_stat, l_reply
	IF l_stat < 400 THEN
		MESSAGE "Processed."
		CALL hmrcLib.disp(SFMT("Process:%1", l_reply))
		CALL newObligationsFromJson(l_reply)
	ELSE
		CALL hmrcLib.errDisp(l_reply)
	END IF
END FUNCTION
--------------------------------------------------------------------------------
-- new Obligations JSON data
FUNCTION newObligationsFromJson(l_data STRING)
	DEFINE l_rec RECORD
		obligations DYNAMIC ARRAY OF t_obligations
	END RECORD
	TRY
		CALL util.JSON.parse(l_data, l_rec)
	CATCH
		CALL hmrcLib.errDisp(SFMT("Failed to Parse JSON Obligations %1-%2", STATUS, ERR_GET(STATUS)))
		RETURN
	END TRY
	CALL newObligationsToDB(l_rec.obligations)
END FUNCTION
--------------------------------------------------------------------------------
-- insert new Obligations into DB if it doesn't already exist.
FUNCTION newObligationsToDB(l_arr DYNAMIC ARRAY OF t_obligations)
--TODO: insert into DB!
	MESSAGE "New Obligations Loaded"
END FUNCTION
--------------------------------------------------------------------------------
