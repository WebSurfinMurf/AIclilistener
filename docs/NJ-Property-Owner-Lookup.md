# NJ Property Owner Lookup Guide

## Overview

New Jersey's statewide MOD-IV property database has **owner names redacted** due to Daniel's Law (P.L. 2020, c.125), which protects the personal information of law enforcement, judges, and other covered persons.

However, **municipal tax collector portals still display owner names** for property lookups. This guide documents how to retrieve owner information by address or block/lot for Union County municipalities.

## How It Works

1. You have property data with block/lot/qualifier from MOD-IV (no owner name)
2. Use the municipal code to determine which portal to query
3. Search by block/lot or address
4. Retrieve owner name from the results

---

## Union County Municipalities

Union County code: **20**
Municipal codes: **2001-2021**

### WIPP Portals (13 municipalities)

These municipalities use the Edmunds WIPP (Web Inquiry Payment Portal) system. **No login required** for property lookups.

| Code | Municipality | WIPP URL |
|------|--------------|----------|
| 2001 | Berkeley Heights | https://wipp.edmundsassoc.com/Wipp/?wippid=2001 |
| 2002 | Clark | https://wipp.edmundsassoc.com/Wipp/?wippid=2002 |
| 2003 | Cranford | https://wipp.edmundsassoc.com/Wipp/?wippid=2003 |
| 2004 | Elizabeth | https://wipp.edmundsassoc.com/Wipp/?wippid=2004 |
| 2005 | Fanwood | https://wipp.edmundsassoc.com/Wipp/?wippid=2005 |
| 2006 | Garwood | https://wipp.edmundsassoc.com/Wipp/?wippid=2006 |
| 2008 | Kenilworth | https://wipp.edmundsassoc.com/Wipp/?wippid=2008 |
| 2009 | Linden | https://wipp.edmundsassoc.com/Wipp/?wippid=2009 |
| 2011 | New Providence | https://wipp.edmundsassoc.com/Wipp/?wippid=2011 |
| 2014 | Roselle | https://wipp.edmundsassoc.com/Wipp/?wippid=2014 |
| 2019 | Union Twp | https://wipp.edmundsassoc.com/Wipp/?wippid=2019 |
| 2020 | Westfield | https://wipp.edmundsassoc.com/Wipp/?wippid=2020 |

**Alternate URL format:** `https://wipp.edmundsassoc.com/Wipp{CODE}/` (e.g., `Wipp2008/`)

### Non-WIPP Municipalities (8 municipalities)

These require alternative lookup methods:

| Code | Municipality | System | Notes |
|------|--------------|--------|-------|
| 2007 | Hillside | CIT-E | https://www.cit-e.net/ - search by block-lot or owner name |
| 2010 | Mountainside | Custom | Contact tax collector: (908) 232-2400 x240 |
| 2012 | Plainfield | CIT-E | https://www.cit-e.net/ - search by block-lot or owner name |
| 2013 | Rahway | Custom | https://www.cityofrahway.com/ - check tax collector page |
| 2015 | Roselle Park | Custom | Contact tax collector: (908) 245-0819 |
| 2016 | Scotch Plains | Custom | https://www.scotchplainsnj.gov/ - check tax collector page |
| 2017 | Springfield | CIT-E | https://www.cit-e.net/summit-nj/ - search by block-lot or owner name |
| 2018 | Summit | CIT-E | https://www.cit-e.net/summit-nj/cn/TaxBill_Std/TaxAmount.cfm |
| 2021 | Winfield | Custom | Contact tax collector: (908) 925-3850 |

---

## Using WIPP for Property Lookups

### Search Options

WIPP portals support searching by:
- **Block/Lot/Qualifier** - Most precise method
- **Property Address** - Street number and name
- **Owner Name** - Last name search

### Step-by-Step

1. **Determine the municipal code** from your property data (`pcl_mun` field)
2. **Navigate to the WIPP URL** for that municipality
3. **Enter search criteria:**
   - For block/lot: Enter block number, lot number, and qualifier (if any)
   - For address: Enter street number and street name
4. **View results** - Owner name displayed in the property details

### Example

For property at 740 Summit Ave, Kenilworth, NJ:
- Municipal code: `2008` (Kenilworth)
- Block: `132`
- Lot: `1`
- URL: https://wipp.edmundsassoc.com/Wipp/?wippid=2008

Search by block `132`, lot `1` to retrieve owner information.

---

## Programmatic Access

### URL Pattern

```
https://wipp.edmundsassoc.com/Wipp/?wippid={MUNICIPAL_CODE}
```

### Considerations

- WIPP sites are **JavaScript-heavy** (require browser automation for scraping)
- No official API available
- Rate limiting may apply
- Consider using Puppeteer, Playwright, or Selenium for automated lookups

### Database Mapping

Your MOD-IV data contains:
- `pcl_mun` (e.g., "2008") - Maps directly to `wippid`
- `pclblock` (e.g., "132") - Block number for search
- `pcllot` (e.g., "1") - Lot number for search
- `pclqcode` (e.g., "C0001") - Qualifier for condos/multi-unit

---

## CIT-E System (Alternative)

For Hillside, Plainfield, Springfield, and Summit, the CIT-E system is used.

### Search Fields
- Block-Lot Qualification
- Owner's Last Name
- Company Name

### URL Pattern
```
https://www.cit-e.net/{municipality}/cn/TaxBill_Std/TaxAmount.cfm
```

---

## Other Counties

The WIPP pattern extends to other NJ counties. The `wippid` corresponds to the NJ municipal code:

| County | Code Range | Example |
|--------|------------|---------|
| Atlantic | 0101-0123 | Atlantic City = 0102 |
| Bergen | 0201-0270 | Hackensack = 0223 |
| Burlington | 0301-0340 | Mount Laurel = 0324 |
| Camden | 0401-0437 | Camden = 0409 |
| Essex | 0701-0722 | Newark = 0714 |
| Hudson | 0901-0912 | Jersey City = 0906 |
| Middlesex | 1201-1225 | Edison = 1205 |
| Monmouth | 1301-1353 | Freehold = 1316 |
| Morris | 1401-1439 | Morristown = 1427 |
| Passaic | 1601-1616 | Paterson = 1613 |
| Somerset | 1801-1821 | Franklin = 1806 |
| Union | 2001-2021 | Elizabeth = 2004 |

Full municipal code list: https://www.nj.gov/treasury/taxation/pdf/lpt/cntycode.pdf

---

## Data Sources

| Source | Owner Names | Block/Lot Search | Coverage | Cost |
|--------|-------------|------------------|----------|------|
| WIPP Portals | Yes | Yes | Per municipality | Free |
| CIT-E | Yes | Yes | Select municipalities | Free |
| NJParcels.com | No (redacted) | Yes | Statewide | Free |
| NJ Transparency Portal | Limited | Map only | Statewide | Free |
| NJPropertyRecords.com | Yes | Yes | Statewide | Paid/API |

---

## Legal Considerations

- Property tax records are public information under NJ Open Public Records Act (OPRA)
- Daniel's Law redacts names from bulk data downloads, not individual lookups
- Automated scraping may violate Terms of Service of municipal portals
- For bulk data needs, consider OPRA requests to individual municipalities

---

## References

- NJ Municipal Codes: https://www.nj.gov/treasury/taxation/pdf/lpt/cntycode.pdf
- Daniel's Law (P.L. 2020, c.125): https://www.njleg.state.nj.us/bill-search/2020/A6171
- Union County Tax Board: https://ucnj.org/taxation-board/
- NJ MOD-IV Data: https://njogis-newjersey.opendata.arcgis.com/

---

*Last Updated: 2025-12-31*
