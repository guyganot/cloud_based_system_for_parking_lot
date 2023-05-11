import datetime
import decimal
import os

import boto3
from boto3.dynamodb.conditions import Key

# Initialize the DynamoDB client
dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('TABLE_NAME')
table = dynamodb.Table(table_name)

# Define the parking lot entry endpoint
def parking_lot_entry(event, context):
    # Parse the license plate and parking lot ID from the request parameters
    plate = event['queryStringParameters']['plate']
    parking_lot = event['queryStringParameters']['parkingLot']
    
    # Get the current timestamp
    timestamp = datetime.datetime.now().timestamp()
    
    # Create a new parking ticket in DynamoDB
    response = table.put_item(
        Item={
            'ticketId': str(timestamp),
            'plate': plate,
            'parkingLot': parking_lot,
            'entryTime': str(timestamp),
        }
    )
    
    # Return the ticket ID as the response
    return {
        'statusCode': 200,
        'body': response['Item']['ticketId'],
    }

# Define the parking lot exit endpoint
def parking_lot_exit(event, context):
    # Parse the ticket ID from the request parameters
    ticket_id = event['queryStringParameters']['ticketId']
    
    # Retrieve the parking ticket from DynamoDB
    response = table.query(
        KeyConditionExpression=Key('ticketId').eq(ticket_id)
    )
    
    # Calculate the total parked time and charge
    entry_time = decimal.Decimal(response['Items'][0]['entryTime'])
    exit_time = decimal.Decimal(datetime.datetime.now().timestamp())
    parked_time = exit_time - entry_time
    parked_hours = parked_time / 3600
    parked_hours_rounded = decimal.Decimal(parked_hours.quantize(decimal.Decimal('.25'), rounding=decimal.ROUND_HALF_UP))
    charge = parked_hours_rounded * decimal.Decimal(10)
    
    # Update the parking ticket with the exit time and charge
    table.update_item(
        Key={
            'ticketId': ticket_id
        },
        UpdateExpression='SET exitTime = :val1, charge = :val2',
        ExpressionAttributeValues={
            ':val1': str(exit_time),
            ':val2': str(charge),
        }
    )
    
    # Return the license plate, parking lot ID, total parked time, and charge as the response
    return {
        'statusCode': 200,
        'body': f"License plate: {response['Items'][0]['plate']}, Parking lot ID: {response['Items'][0]['parkingLot']}, Total parked time: {parked_hours_rounded} hours, Charge: {charge}",
    }
