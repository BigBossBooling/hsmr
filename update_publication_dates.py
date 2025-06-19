#!/usr/bin/env python3
import re
from datetime import datetime, timedelta

def get_previous_quarter_end_date(today):
    """
    Calculates the end date (last day) of the quarter preceding the one `today` falls into.
    """
    current_month = today.month
    current_year = today.year

    if 1 <= current_month <= 3:  # Currently in Q1, previous was Q4 of last year
        previous_quarter_month = 12
        previous_quarter_year = current_year - 1
    elif 4 <= current_month <= 6:  # Currently in Q2, previous was Q1 of current year
        previous_quarter_month = 3
        previous_quarter_year = current_year
    elif 7 <= current_month <= 9:  # Currently in Q3, previous was Q2 of current year
        previous_quarter_month = 6
        previous_quarter_year = current_year
    else:  # Currently in Q4, previous was Q3 of current year
        previous_quarter_month = 9
        previous_quarter_year = current_year

    if previous_quarter_month == 12:
        end_of_previous_quarter = datetime(previous_quarter_year + 1, 1, 1) - timedelta(days=1)
    else:
        end_of_previous_quarter = datetime(previous_quarter_year, previous_quarter_month + 1, 1) - timedelta(days=1)

    return end_of_previous_quarter

def update_r_script_dates(r_script_path="setup_environment.R"):
    """
    Updates the end_date in the R script to the last day of the previous quarter.
    """
    # Use a fixed date for predictable testing in this environment.
    # In a real scenario, this would be datetime.today().
    # This date (June 19, 2025) means the previous quarter ended March 31, 2025.
    today = datetime(2025, 6, 19)

    new_end_date_obj = get_previous_quarter_end_date(today)
    new_end_date_dmy_format = new_end_date_obj.strftime("%d%m%Y")

    print(f"Fixed 'today' for testing: {today.strftime('%Y-%m-%d')}")
    print(f"Calculated new end_date: {new_end_date_obj.strftime('%Y-%m-%d')}")
    print(f"Formatted new end_date for R script (DDMMYYYY): {new_end_date_dmy_format}")

    try:
        with open(r_script_path, 'r', encoding='utf-8') as file:
            content = file.read()
    except FileNotFoundError:
        print(f"Error: R script '{r_script_path}' not found.")
        return False
    except Exception as e:
        print(f"Error reading file '{r_script_path}': {e}")
        return False

    # Adjusted Regex:
    # Looks for "end_date", whitespace, "<-", whitespace, "lubridate::dmy(", digits, ")"
    # This is more robust to comment changes on the line.
    pattern = r"^(end_date\s*<-\s*lubridate::dmy\()(\d+)(\))"

    if not re.search(pattern, content, re.MULTILINE):
        print(f"Error: Pattern for 'end_date' not found in '{r_script_path}'.")
        print(f"Expected pattern like: end_date <- lubridate::dmy(DDMMYYYY)")
        return False

    replacement_string = r"\g<1>" + new_end_date_dmy_format + r"\g<3>"
    new_content, num_replacements = re.subn(pattern, replacement_string, content, flags=re.MULTILINE)

    if num_replacements == 0:
        print(f"Warning: 'end_date' pattern was matched by search but not substituted by subn. This is unexpected.")
        return False
    elif num_replacements > 1:
        print(f"Warning: Multiple lines ({num_replacements}) matched the 'end_date' pattern in '{r_script_path}'. All were updated.")

    try:
        with open(r_script_path, 'w', encoding='utf-8') as file:
            file.write(new_content)
        print(f"Successfully updated 'end_date' in '{r_script_path}' to {new_end_date_dmy_format}.")
        return True
    except Exception as e:
        print(f"Error writing updated content to '{r_script_path}': {e}")
        return False

if __name__ == "__main__":
    if not update_r_script_dates():
        print("Date update script failed.")
    else:
        print("Date update script completed.")
