
IMPORT util
IMPORT os
IMPORT FGL hmrcLib
IMPORT FGL hmrcRest

&include "hmrcLib.inc"

DEFINE m_orgs DYNAMIC ARRAY OF t_hmrcOrganisations
DEFINE m_toks DYNAMIC ARRAY OF t_hmrcAccessToken
DEFINE m_arr DYNAMIC ARRAY OF RECORD
  	userId VARCHAR(30),
  	userFullName VARCHAR(100),
  	emailAddress VARCHAR(200),
    org_name VARCHAR(20),
  	vrn VARCHAR(20),
		stat CHAR(1)
	END RECORD
DEFINE m_getTokenURL, m_clientId, m_secretId STRING
MAIN
	DEFINE l_orgno SMALLINT

	LET m_getTokenURL = fgl_getEnv("GRANTURL")
	LET m_clientId = fgl_getEnv("CLIENT_PUBLIC_ID")
	LET m_secretId = fgl_getEnv("CLIENT_SECRET_ID")

	OPEN FORM hmrcDemo FROM "hmrcDemo"
	DISPLAY FORM hmrcDemo

	IF NOT connectToDB() THEN
		CALL fgl_winMessage("Error", hmrcLib.m_db_err, "exclamation")
		EXIT PROGRAM
	END IF
	CALL chkTables()

	CALL setupOrganisationArray()

	IF m_orgs.getLength() = 0 THEN
		CALL loadFromJson(os.path.join(fgl_getEnv("BASE"),"ac1.json"))
	END IF
	CALL setupScreenArray()

	DISPLAY ARRAY m_arr TO arr.* ATTRIBUTES(ACCEPT=FALSE, CANCEL=FALSE, UNBUFFERED)
		BEFORE ROW
			LET l_orgno = arr_curr()
			DISPLAY BY NAME m_orgs[ l_orgno ].userId, m_orgs[ l_orgno ].password
			DISPLAY "" TO l_url
			CALL DIALOG.setActionActive("gettok", FALSE)
			CALL DIALOG.setActionActive("gettok_wc", FALSE)
			CALL DIALOG.setActionActive("refreshok", FALSE)
			IF m_arr[ l_orgno ].stat MATCHES "[NE]" THEN
				CALL DIALOG.setActionActive("gettok", TRUE)
				CALL DIALOG.setActionActive("gettok_wc", TRUE)
			END IF
			IF m_arr[ l_orgno ].stat = "E" THEN
				CALL DIALOG.setActionActive("refreshok", TRUE)
			END IF

		ON ACTION neworg CALL hmrcNewOrganisation()

		ON ACTION refreshok CALL hmrcRefreshToken(l_orgno)

		ON ACTION gettok CALL getToken(l_orgno)

		ON ACTION gettok_wc CALL getToken_wc(l_orgno)

		ON ACTION obligations CALL getObligations(l_orgno)

		ON ACTION quit EXIT DISPLAY
		ON ACTION close EXIT DISPLAY
	END DISPLAY

END MAIN
--------------------------------------------------------------------------------
-- build array of the Organisations
FUNCTION setupOrganisationArray()
	CALL m_orgs.clear()
	DECLARE cur1 CURSOR FOR SELECT * FROM hmrcOrganisations
	FOREACH cur1 INTO m_orgs[ m_orgs.getLength() + 1 ].*
	END FOREACH
	CALL m_orgs.deleteElement( m_orgs.getLength() )
END FUNCTION
--------------------------------------------------------------------------------
-- build array for the screen.
FUNCTION setupScreenArray()
	DEFINE x SMALLINT
	CALL m_arr.clear()
	CALL m_toks.clear()
	FOR x = 1 TO m_orgs.getLength()
		LET m_arr[ x ].userId = m_orgs[x ].userId
		LET m_arr[ x ].emailAddress = m_orgs[ x ].emailAddress
		LET m_arr[ x ].org_name = m_orgs[ x ].org_name
		LET m_arr[ x ].userFullName = m_orgs[ x ].userFullName
		LET m_arr[ x ].vrn = m_orgs[ x ].vrn
		CALL getTokenForOrgFromDB( x  )
	END FOR
END FUNCTION
--------------------------------------------------------------------------------
-- try and get the token for the Organisation from the DB and set the state.
FUNCTION getTokenForOrgFromDB( l_orgno SMALLINT )
	SELECT * INTO m_toks[ l_orgno ].* FROM hmrcAccessTokens WHERE vrn = m_orgs[ l_orgno ].vrn
	IF STATUS = 0 THEN
		IF m_toks[ l_orgno ].token_expires > CURRENT THEN
			LET m_arr[ l_orgno ].stat = "Y" -- valid
		ELSE
			LET m_arr[ l_orgno ].stat = "E" -- expired
		END IF
	ELSE
		LET m_arr[ l_orgno ].stat = "N" -- no token
	END IF
END FUNCTION
--------------------------------------------------------------------------------
-- get the Token by calling oauth program.
FUNCTION getToken( l_orgno SMALLINT )
	DEFINE l_url STRING
	LET l_url = m_getTokenURL||"?Arg1="||m_orgs[ l_orgno ].vrn
	DISPLAY BY NAME l_url
	CALL ui.Interface.frontCall("standard", "launchURL", [l_url], [] )
	MENU
		COMMAND "Grant Done" EXIT MENU
	END MENU
	CALL getTokenForOrgFromDB( l_orgno  )
END FUNCTION
--------------------------------------------------------------------------------
-- get the Token by calling oauth program in a WebComponent
FUNCTION getToken_wc( l_orgno SMALLINT )
	DEFINE l_url STRING
	OPEN WINDOW getToken_wc WITH FORM "getToken_wc"
	LET l_url = m_getTokenURL||"?Arg1="||m_orgs[ l_orgno ].vrn
	DISPLAY BY NAME m_orgs[ l_orgno ].userId, m_orgs[ l_orgno ].password, l_url
	DISPLAY l_url TO wc
	MENU
		COMMAND "Grant Done" EXIT MENU
		ON ACTION close EXIT MENU
	END MENU
	CALL getTokenForOrgFromDB( l_orgno  )
	CLOSE WINDOW getToken_wc
END FUNCTION
--------------------------------------------------------------------------------
-- Refresh the token for the Organisation
FUNCTION hmrcRefreshToken( l_orgno SMALLINT )
	DEFINE l_req_data, l_data STRING
	DEFINE l_stat SMALLINT
	DEFINE l_hmrcToken t_hmrcAccessToken
	DEFINE l_refresh_rec RECORD
			access_token STRING,
			refresh_token STRING,
			expires_in STRING,
			scope STRING,
			token_type STRING
		END RECORD

	LET l_req_data = 
		SFMT( "client_secret=%1&client_id=%2&grant_type=refresh_token&refresh_token=%3", m_secretId, m_clientId, m_toks[ l_orgno ].refresh_token )
	DISPLAY m_toks[ l_orgno ].token_endpoint TO l_url
	CALL hmrcRest.request( m_toks[ l_orgno ].token_endpoint, NULL, l_req_data ) RETURNING l_stat, l_data
	IF l_stat > 300 THEN
		CALL hmrcLib.errDisp2("Failed! "||l_stat, m_toks[ l_orgno ].token_endpoint, l_data)
		RETURN
	END IF
	TRY
		CALL hmrcLib.disp(l_data)
		CALL util.JSON.parse(l_data, l_refresh_rec )
		CALL hmrcLib.disp("Refresh New Token:"||l_refresh_rec.access_token)
	CATCH
		CALL hmrcLib.disp("JSON Parse failed!")
		RETURN
	END TRY

	IF NOT hmrcLib.updateTokenInDB(l_hmrcToken.*) THEN
		CALL hmrcLib.errDisp(hmrcLib.m_db_err)
	ELSE
		MESSAGE "Token Registered"
	END IF
END FUNCTION
--------------------------------------------------------------------------------
-- Create a new Test Organisation using the API
FUNCTION hmrcNewOrganisation()
	DEFINE l_data STRING
	DEFINE l_stat SMALLINT
	DEFINE l_reply, l_url, l_srv_token STRING
	LET l_url = fgl_getEnv("HMRC_URL")||"/create-test-user/organisations"
	DISPLAY BY NAME l_url
	LET l_srv_token = fgl_getEnv("SERVER_TOKEN")
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
	CALL hmrcRest.request(l_url, l_srv_token, l_data )
		RETURNING l_stat, l_reply
	IF l_stat < 400 THEN
		CALL newOranisationFromJson( l_reply )
	ELSE
		CALL hmrcLib.errDisp( l_reply )
	END IF
END FUNCTION
--------------------------------------------------------------------------------
-- insert new Organisation into DB if it doesn't already exist.
FUNCTION hmrcNewOrganisationToDB( l_rec )
	DEFINE l_rec t_hmrcOrganisations
	SELECT * FROM hmrcOrganisations WHERE vrn = l_rec.vrn
	IF STATUS = NOTFOUND THEN
		INSERT INTO hmrcOrganisations VALUES( l_rec.* )
		DISPLAY "Organisation Inserted."
	ELSE
		ERROR "Organisation Exists!"
	END IF
ENd FUNCTION
--------------------------------------------------------------------------------
-- load example from JSON file
FUNCTION loadFromJson( l_fileName STRING  )
	DEFINE l_data TEXT
-- read JSON file
	LOCATE l_data IN FILE l_fileName
	CALL newOranisationFromJson( l_data )
END FUNCTION
--------------------------------------------------------------------------------
-- load example from JSON file
FUNCTION newOranisationFromJson( l_data STRING  )
	DEFINE l_recJSON t_hmrcOrganisationsJSON
	DEFINE l_rec t_hmrcOrganisations

-- populate FULL 4gl record from JSON
	CALL util.JSON.parse( l_data, l_recJSON )
-- populate flat 4gl record from JSON
	CALL util.JSON.parse( l_data, l_rec )
-- add missing non-flat fields to flat record.
	LET l_rec.org_name = l_recJSON.organisationDetails.name
	LET l_rec.org_address_line1 = l_recJSON.organisationDetails.address.line1
	LET l_rec.org_address_line2 = l_recJSON.organisationDetails.address.line2
	LET l_rec.org_address_pcode = l_recJSON.organisationDetails.address.postcode
	IF l_rec.vrn IS NULL THEN
		ERROR "Organisation missing VRN!"
		RETURN
	END IF

-- add to the array
	LET m_orgs[ m_orgs.getLength() + 1 ].* = l_rec.*

-- insert into DB.
	CALL hmrcNewOrganisationToDB(l_rec.*)

END FUNCTION
--------------------------------------------------------------------------------
-- get Obligations from the HMRC for the Organisation
FUNCTION getObligations( l_orgno SMALLINT )
	DEFINE l_url, l_reply STRING
	DEFINE l_stat SMALLINT
	DEFINE l_vatno STRING
	DEFINE l_from,  l_to DATE
	DEFINE l_status CHAR(1)

	LET l_vatno = m_orgs[ l_orgno ].vrn
	LET l_from = "2018-04-06"
	LET l_to = "2019-04-05"
	LET l_status = "O"

	LET int_flag = FALSE
	INPUT BY NAME l_from, l_to, l_status WITHOUT DEFAULTS
	IF int_flag THEN LET int_flag = FALSE RETURN END IF

	LET l_url = SFMT("%1/organisations/vat/%2/obligations?from=%3&to=%4&status=%5",fgl_getEnv("HMRC_URL"),l_vatno, l_from, l_to, l_status)
	DISPLAY BY NAME l_url
	CALL hmrcRest.request( l_url, m_toks[ l_orgno ].token, "" ) RETURNING l_stat, l_reply
	IF l_stat < 400 THEN
		MESSAGE "Processed."
		CALL disp(SFMT("Process:%1",l_reply))
	ELSE
		CALL hmrcLib.errDisp( l_reply )
	END IF
END FUNCTION
--------------------------------------------------------------------------------