import json
import time
from flask import Flask, request, Response

app = Flask(__name__)

parked_cars = {}
plate_id_in_lot = set()
occupied_parking_lot_number = set()

@app.route('/entry', methods=['POST'])
def entry():
    plate_id = request.form.get('plate')
    parking_lot_number = request.form.get('parkingLot')
    if not plate_id or not parking_lot_number:
        return Response(
            response=json.dumps({'error': 'Invalid request. Please provide both plate and parkingLot.'}),
            status=400,
            mimetype='application/json'
        )
    if plate_id in plate_id_in_lot:
        return Response(
            response=json.dumps({'error': 'Invalid request. Plate ID is already in the parking lot.'}),
            status=400,
            mimetype='application/json'
        )
    if parking_lot_number in occupied_parking_lot_number:
        return Response(
            response=json.dumps({'error': 'Invalid request. The parking lot number you enter is occupied.'}),
            status=400,
            mimetype='application/json'
        )

    ticket_id = str(int(time.time())) # generate unique ticket id based on timestamp
    parked_cars[ticket_id] = {
        'entry_time': time.time(),
        'plate_id': plate_id,
        'parking_lot_number': parking_lot_number,
    }

    plate_id_in_lot.add(plate_id)
    occupied_parking_lot_number.add(parking_lot_number)
    response = {'ticket_id': ticket_id}
    return Response(
        response=json.dumps(response),
        status=200,
        mimetype='application/json'
    )


@app.route('/exit', methods=['POST'])
def exit():
    ticket_id = request.form.get('ticketId')
    if not ticket_id:
        return Response(
            response=json.dumps({'error': 'Invalid request. Please provide ticketId.'}),
            status=400,
            mimetype='application/json'
        )

    if ticket_id not in parked_cars:
        return Response(
            response=json.dumps({'error': 'Invalid ticketId. No car found for the given ticketId.'}),
            status=404,
            mimetype='application/json'
        )

    parked_car = parked_cars[ticket_id]
    entry_time = parked_car['entry_time']
    parked_time_in_seconds = time.time() - entry_time
    parked_time_in_minutes = int(parked_time_in_seconds / 60)
    parked_time_in_hours = parked_time_in_minutes // 60
    parked_time_in_quarters = (parked_time_in_minutes % 60) // 15
    total_charge = (parked_time_in_hours * 4 + parked_time_in_quarters) * 2.5

    response = {
        'plate_id': parked_car['plate_id'],
        'parked_time': f'{parked_time_in_hours}h {parked_time_in_minutes}m',
        'charge': f'${total_charge}'
    }

    del parked_cars[ticket_id]
    plate_id_in_lot.remove(parked_car['plate_id'])
    occupied_parking_lot_number.remove(parked_car['parking_lot_number'])
    return Response(
        response=json.dumps(response),
        status=200,
        mimetype='application/json'
    )


if __name__ == '__main__':
    app.run(debug=True)
