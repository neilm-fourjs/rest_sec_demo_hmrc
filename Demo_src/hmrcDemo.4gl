
IMPORT util
IMPORT os

&include "hmrcLib.inc"

DEFINE m_orgs DYNAMIC ARRAY OF t_hmrcOrganisations
DEFINE m_toks DYNAMIC ARRAY OF t_hmrcAccessTokens
DEFINE m_arr DYNAMIC ARRAY OF RECORD
  	userId VARCHAR(30),
  	userFullName VARCHAR(100),
  	emailAddress VARCHAR(200),
    org_name VARCHAR(20),
  	vrn VARCHAR(20),
		stat CHAR(1)
	END RECORD
DEFINE m_getTokenURL STRING
MAIN
	DEFINE l_dbName STRING

	LET l_dbName = fgl_getEnv("DBNAME")
	LET m_getTokenURL = fgl_getEnv("GRANTURL")
	
	OPEN FORM hmrcDemo FROM "hmrcDemo"
	DISPLAY FORM hmrcDemo

	TRY
		CONNECT TO l_dbName
	CATCH
		DISPLAY SFMT( "Error for DB '%1':%2", l_dbName ,SQLERRMESSAGE )
		EXIT PROGRAM
	END TRY

	CALL chkTables()

	DECLARE cur1 CURSOR FOR SELECT * FROM hmrcOrganisations
	FOREACH cur1 INTO m_orgs[ m_orgs.getLength() + 1 ].*
	END FOREACH
	CALL m_orgs.deleteElement( m_orgs.getLength() )

	IF m_orgs.getLength() = 0 THEN
		CALL loadFromJson(os.path.join(fgl_getEnv("BASE"),"ac1.json"))
	END IF
	CALL getTokensForOrgs()

	DISPLAY ARRAY m_arr TO arr.*
		BEFORE ROW
			IF m_arr[ arr_curr() ].stat != "Y" THEN
				CALL DIALOG.setActionActive("gettok", TRUE)
			ELSE
				CALL DIALOG.setActionActive("gettok", FALSE)
			END IF
		ON ACTION close EXIT DISPLAY
		ON ACTION neworg CALL newOrg()
		ON ACTION gettok 
			IF m_arr[ arr_curr() ].stat != "Y" THEN CALL getToken(arr_curr()) END IF
	END DISPLAY

END MAIN
--------------------------------------------------------------------------------
FUNCTION getTokensForOrgs()
	DEFINE x SMALLINT
	CALL m_arr.clear()
	CALL m_toks.clear()
	FOR x = 1 TO m_orgs.getLength()
		LET m_arr[ x ].userId = m_orgs[x ].userId
		LET m_arr[ x ].emailAddress = m_orgs[ x ].emailAddress
		LET m_arr[ x ].org_name = m_orgs[ x ].org_name
		LET m_arr[ x ].userFullName = m_orgs[ x ].userFullName
		LET m_arr[ x ].vrn = m_orgs[ x ].vrn
		CALL getTokenForOrg( x  )
	END FOR
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION getTokenForOrg( orgno SMALLINT )
	SELECT * INTO m_toks[ orgno ].* FROM hmrcAccessTokens WHERE vrn = m_orgs[ orgno ].vrn
	IF STATUS = 0 THEN
		DISPLAY "Expires:",m_toks[ orgno ].token_expires," Current:",CURRENT
		IF m_toks[ orgno ].token_expires > CURRENT THEN
			LET m_arr[orgno ].stat = "Y" -- valid
		ELSE
			LET m_arr[ orgno ].stat = "E" -- expired
		END IF
	ELSE
		LET m_arr[ orgno ].stat = "N" -- no token
	END IF
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION getToken( orgno SMALLINT)

	LET m_getTokenURL = m_getTokenURL||"?Arg1="||m_orgs[ orgno ].vrn
	CALL ui.Interface.frontCall("standard", "launchURL", [m_getTokenURL], [] )
	MENU
		COMMAND "Grant Done" EXIT MENU
	END MENU
	CALL getTokenForOrg( orgno  )

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION newOrg()

END FUNCTION
--------------------------------------------------------------------------------
FUNCTION chkTables()
	TRY
		CREATE TABLE hmrcAccessTokens (
			vrn VARCHAR(20),
			token VARCHAR(64), 
			refresh_token VARCHAR(64),
			token_endpoint VARCHAR(200),
			token_expires DATETIME YEAR TO SECOND
		)
		DISPLAY  "Table hmrcAccessTokens created."
	CATCH
		DISPLAY "Table hmrcAccessTokens already exists"
	END TRY

	TRY
		CREATE TABLE hmrcOrganisations (
			userId VARCHAR(30),
			password VARCHAR(30),
			userFullName VARCHAR(100),
			emailAddress VARCHAR(200),
			org_name VARCHAR(20),
			org_address_line1 VARCHAR(100),
			org_address_line2 VARCHAR(100),
			org_address_pcode VARCHAR(10),
			saUtr VARCHAR(20),
			nino VARCHAR(20),
			mtdItId VARCHAR(25),
			mpRef VARCHAR(25),
			ctUtr VARCHAR(20),
			vrn VARCHAR(20),
			vatRegistrationDate DATE,
			lisaManagerReferenceNumber VARCHAR(20),
			secureElectronicTransferReferenceNumber VARCHAR(20),
			pensionSchemeAdministratorIdentifier VARCHAR(20),
			eoriNumber VARCHAR(20)
		)
		DISPLAY  "Table hmrcOrganisations created."
	CATCH
		DISPLAY "Table hmrcOrganisations already exists"
	END TRY
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION hmrcNewAccount(l_rec)
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
FUNCTION loadFromJson( l_fileName STRING  )
	DEFINE l_data TEXT
	DEFINE l_recJSON t_hmrcOrganisationsJSON
	DEFINE l_rec t_hmrcOrganisations
-- read JSON file
	LOCATE l_data IN FILE l_fileName
	DISPLAY l_data
-- populate FULL 4gl record from JSON
	CALL util.JSON.parse( l_data, l_recJSON )
-- populate flat 4gl record from JSON
	CALL util.JSON.parse( l_data, l_rec )
-- add missing non-flat fields to flat record.
	LET l_rec.org_name = l_recJSON.organisationDetails.name
	LET l_rec.org_address_line1 = l_recJSON.organisationDetails.address.line1
	LET l_rec.org_address_line2 = l_recJSON.organisationDetails.address.line2
	LET l_rec.org_address_pcode = l_recJSON.organisationDetails.address.postcode
-- add to the array
	LET m_orgs[1].* = l_rec.*

-- insert into DB.
	CALL hmrcNewAccount(l_rec.*)

ENd FUNCTION
--------------------------------------------------------------------------------