import requests
import json
import time
from typing import Dict, Any

def fetch_all_solar_systems(base_url: str, output_file: str = "solar_systems_mapping.json") -> Dict[str, int]:
    """
    Fetches all solar systems from the API and creates a name-to-ID mapping.
    
    Args:
        base_url: The base URL of the API
        output_file: The filename to save the JSON mapping
    
    Returns:
        Dictionary mapping solar system names to their IDs
    """
    
    endpoint = f"{base_url}/v2/solarsystems"
    solar_systems_mapping = {}
    
    # Initial request to get total count
    print("Fetching initial data to determine total solar systems...")
    
    try:
        response = requests.get(endpoint, params={"limit": 100, "offset": 0})
        response.raise_for_status()
        data = response.json()
        print(data)
        
        total_systems = data["metadata"]["total"]
        limit = data["metadata"]["limit"]
        
        print(f"Total solar systems to fetch: {total_systems}")
        print(f"Limit per request: {limit}")
        print(f"Estimated requests needed: {(total_systems + limit - 1) // limit}")
        
        # Process first batch
        for system in data["data"]:
            solar_systems_mapping[system["name"]] = system["id"]
        
        print(f"Processed first batch: {len(data['data'])} systems")
        
        # Continue fetching remaining batches
        offset = limit
        batch_number = 2
        
        while offset < total_systems:
            print(f"Fetching batch {batch_number} (offset: {offset})...")
            
            try:
                response = requests.get(endpoint, params={"limit": limit, "offset": offset})
                response.raise_for_status()
                batch_data = response.json()
                
                # Process this batch
                for system in batch_data["data"]:
                    solar_systems_mapping[system["name"]] = system["id"]
                
                print(f"Processed batch {batch_number}: {len(batch_data['data'])} systems")
                print(f"Total systems collected so far: {len(solar_systems_mapping)}")
                
                offset += limit
                batch_number += 1
                
                # Small delay to be respectful to the API
                time.sleep(0.1)
                
            except requests.exceptions.RequestException as e:
                print(f"Error fetching batch at offset {offset}: {e}")
                print("Retrying in 5 seconds...")
                time.sleep(5)
                continue
                
    except requests.exceptions.RequestException as e:
        print(f"Error with initial request: {e}")
        return {}
    
    print(f"\nFetching complete! Total systems collected: {len(solar_systems_mapping)}")
    
    # Save to JSON file
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(solar_systems_mapping, f, indent=2, ensure_ascii=False)
        print(f"Solar systems mapping saved to: {output_file}")
    except IOError as e:
        print(f"Error saving to file: {e}")
    
    return solar_systems_mapping

def main():
    """Main function to run the solar systems fetcher."""
    
    base_url = "https://blockchain-gateway-stillness.live.tech.evefrontier.com"
    
    print("Starting solar systems data collection...")
    print(f"Base URL: {base_url}")
    
    mapping = fetch_all_solar_systems(base_url)
    
    if mapping:
        print(f"\nSuccess! Created mapping with {len(mapping)} solar systems.")
        
        # Display a few examples
        print("\nSample mappings:")
        for i, (name, system_id) in enumerate(list(mapping.items())[:5]):
            print(f"  '{name}' -> {system_id}")
        
        if len(mapping) > 5:
            print("  ...")
    else:
        print("Failed to create mapping.")

if __name__ == "__main__":
    main()