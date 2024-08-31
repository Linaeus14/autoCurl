# Copyright 2024 Linaeus14
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import sys
import pandas as pd
from datetime import datetime
import os

# Filename to store the name of the latest Excel file
LATEST_FILE_NAME = 'temp/name.txt'


def get_excel_filename():
    # Generate a filename with the current date and time
    now = datetime.now()
    timestamp = now.strftime('%Y_%m_%d_T_%H_%M_%S')
    return f'report_D_{timestamp}.xlsx'


def initialize_excel():
    # Create an Excel file with the necessary columns if it doesn't exist
    excel_file = get_excel_filename()
    df = pd.DataFrame(
        columns=[
            'Link',
            'Status',
            'SSL Status',
            'Days Until Expiration',
            'Redirect',
            'Content',
            'Date'
        ])
    df.to_excel(excel_file, index=False)
    # Save the filename of the created Excel file
    os.makedirs(os.path.dirname(LATEST_FILE_NAME),
                exist_ok=True)  # Ensure directory exists
    with open(LATEST_FILE_NAME, 'w') as f:
        f.write(excel_file)
    print(f"Excel file '{excel_file}' created.")


def get_latest_excel_file():
    # Retrieve the filename of the latest Excel file
    if os.path.exists(LATEST_FILE_NAME):
        with open(LATEST_FILE_NAME, 'r') as f:
            return f.read().strip()
    else:
        print("No latest file record found. Please initialize first.")
        sys.exit(1)


def append_row(link, status, ssl_status, days_until_expiration, redirect, content):
    # Retrieve the latest Excel file
    excel_file = get_latest_excel_file()
    # Append a row with the current data to the Excel file
    df = pd.read_excel(excel_file)
    new_row = pd.DataFrame({
        'Link': [link],
        'Status': [status],
        'SSL Status': [ssl_status],
        'Days Until Expiration': [days_until_expiration],
        'Redirect': [redirect],
        'Content': [content],
        'Date': [datetime.now().strftime('%Y-%m-%d %H:%M:%S')]
    })
    df = pd.concat([df, new_row], ignore_index=True)
    df.to_excel(excel_file, index=False)


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == 'initialize':
        initialize_excel()
    elif len(sys.argv) == 7:
        link = sys.argv[1]
        status = sys.argv[2]
        ssl_status = sys.argv[3]
        days_until_expiration = sys.argv[4]
        redirect = sys.argv[5]
        content = sys.argv[6]
        append_row(
            link,
            status,
            ssl_status,
            days_until_expiration,
            redirect,
            content
        )
    else:
        print(
            "Invalid arguments. Usage:\n"
            "  python script.py initialize\n"
            "  python script.py <link> <status> <redirect> <ssl_status> <days_until_expiration> <content>"
        )
